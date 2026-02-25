#!/usr/bin/env bash
# =============================================================================
# shopizer-admin/start.sh — Admin UI (Angular) Start Script
# Handles first-time setup: Homebrew, nvm, Node 16, Python 3.10, npm install
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOGS_DIR/admin.log"
PID_FILE="$SCRIPT_DIR/.admin.pid"
NODE_VERSION="16"

mkdir -p "$LOGS_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()     { echo "[$(date '+%H:%M:%S')] $*"; }
section() { echo ""; echo "── $1 ──────────────────────────────────────────"; }

fatal() {
  local msg="$1" cmd="${2:-N/A}" code="${3:-1}"
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  ✗ ADMIN START FAILED                            ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo "  Error   : $msg"
  echo "  Command : $cmd"
  echo "  Exit    : $code"
  echo "  Log     : $LOG_FILE"
  echo ""
  echo "┄┄┄┄┄┄ PASTE THE BLOCK BELOW INTO CLAUDE CODE CLI TO FIX ┄┄┄┄┄┄"
  echo ""
  echo "The script shopizer-admin/start.sh failed. Please fix it."
  echo "Error: $msg"
  echo "Failed command: $cmd"
  echo "Exit code: $code"
  echo "OS: $(uname -s) $(uname -m)"
  echo "Node: $(node --version 2>/dev/null || echo 'not found')"
  echo "npm: $(npm --version 2>/dev/null || echo 'not found')"
  echo "Python: $(python3 --version 2>/dev/null || echo 'not found')"
  echo "Script: $SCRIPT_DIR/start.sh"
  echo "Recent log:"
  tail -20 "$LOG_FILE" 2>/dev/null || echo "(no log yet)"
  echo ""
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  exit 1
}

# ── Homebrew ──────────────────────────────────────────────────────────────────

setup_brew() {
  section "Homebrew"
  if ! command -v brew &>/dev/null; then
    log "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || fatal "Failed to install Homebrew" "homebrew install script"
    [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f /usr/local/bin/brew   ]] && eval "$(/usr/local/bin/brew shellenv)"
  fi
  log "✓ $(brew --version | head -1)"
}

# ── nvm ───────────────────────────────────────────────────────────────────────

setup_nvm() {
  section "nvm"
  export NVM_DIR="$HOME/.nvm"

  if [[ ! -d "$NVM_DIR" ]]; then
    log "nvm not found. Installing..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
      || fatal "Failed to install nvm" "curl nvm install script"
  fi

  # Load nvm in this script session
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

  command -v nvm &>/dev/null \
    || fatal "nvm installed but failed to load" "source \$NVM_DIR/nvm.sh"

  log "✓ nvm $(nvm --version)"
}

# ── Node 16 ───────────────────────────────────────────────────────────────────

setup_node() {
  section "Node.js $NODE_VERSION"
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  if ! nvm ls "$NODE_VERSION" &>/dev/null; then
    log "Node $NODE_VERSION not found. Installing..."
    nvm install "$NODE_VERSION" \
      || fatal "Failed to install Node $NODE_VERSION" "nvm install $NODE_VERSION"
  fi

  nvm use "$NODE_VERSION" \
    || fatal "Failed to switch to Node $NODE_VERSION" "nvm use $NODE_VERSION"

  log "✓ Node $(node --version) | npm $(npm --version)"
}

# ── npm install ───────────────────────────────────────────────────────────────
# We use --ignore-scripts to skip fibers' native ARM64-incompatible build.
# ngcc (the Angular compat compiler) is then run manually since its postinstall
# hook is also skipped by --ignore-scripts.

run_npm_install() {
  section "npm install"
  cd "$SCRIPT_DIR"

  # Hash-based skip: only reinstall when package.json or package-lock.json change.
  local LOCK_HASH STORED_HASH
  LOCK_HASH=$(md5 -q "$SCRIPT_DIR/package.json" "$SCRIPT_DIR/package-lock.json" 2>/dev/null || echo "")
  STORED_HASH=$(cat "$SCRIPT_DIR/.npm_install_hash" 2>/dev/null || echo "none")

  if [[ "$LOCK_HASH" == "$STORED_HASH" ]] && [[ -d "$SCRIPT_DIR/node_modules" ]]; then
    log "Dependencies up-to-date (package files unchanged). Skipping npm install + ngcc."
  else
    log "Running: npm install --legacy-peer-deps --ignore-scripts"
    npm install --legacy-peer-deps --ignore-scripts \
      || fatal "npm install failed" "npm install --legacy-peer-deps --ignore-scripts"

    # Remove fibers — incompatible with Apple Silicon (ARM64) at runtime.
    # With --ignore-scripts its native binary was never built, but removing the
    # directory prevents any JS stub from crashing when sass looks for it.
    if [[ -d "$SCRIPT_DIR/node_modules/fibers" ]]; then
      log "Removing fibers (ARM64-incompatible)..."
      rm -rf "$SCRIPT_DIR/node_modules/fibers"
    fi

    # Run ngcc manually (the postinstall hook was skipped by --ignore-scripts).
    # ngcc converts Angular libraries for View Engine / Ivy compatibility.
    log "Running ngcc (Angular compatibility compiler — this takes ~30-60s)..."
    "$SCRIPT_DIR/node_modules/.bin/ngcc" \
      --properties es2015 es5 browser module main \
      --first-only --create-ivy-entry-points \
      || fatal "ngcc failed" "ngcc"

    # Store the hash so we skip on next run if nothing changed.
    echo "$LOCK_HASH" > "$SCRIPT_DIR/.npm_install_hash"
    log "✓ Dependencies installed and ngcc complete"
  fi
}

# ── ng serve ──────────────────────────────────────────────────────────────────

start_admin() {
  section "Starting Angular Dev Server"
  cd "$SCRIPT_DIR"

  # Stop any existing instance
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
      log "Stopping existing admin server (PID: $OLD_PID)..."
      kill "$OLD_PID" 2>/dev/null || true
      sleep 2
    fi
    rm -f "$PID_FILE"
  fi

  # Kill anything on port 4200
  lsof -ti:4200 | xargs kill -9 2>/dev/null || true

  log "Running: npm start (ng serve)"
  log "Logging to: $LOG_FILE"

  npm start >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  log "✓ Admin started (PID: $(cat "$PID_FILE"))"
  log "  URL  : http://localhost:4200"
  log "  Logs : tail -f $LOG_FILE"
  log "  Stop : $SCRIPT_DIR/stop.sh"
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Shopizer Admin UI — Setup & Start               ║"
echo "╚══════════════════════════════════════════════════╝"

setup_brew
setup_nvm
setup_node
run_npm_install
start_admin

echo ""
log "Done. Admin UI is starting up (first load may take ~30s for Angular to compile)."
