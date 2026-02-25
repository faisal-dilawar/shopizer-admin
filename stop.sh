#!/usr/bin/env bash
# =============================================================================
# shopizer-admin/stop.sh — Admin UI (Angular) Stop Script
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.admin.pid"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Shopizer Admin UI — Stop                        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "── Angular Dev Server ──────────────────────────────────"

STOPPED=false

if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    log "Stopping admin server (PID: $PID)..."
    kill "$PID" 2>/dev/null || true
    sleep 2
    if kill -0 "$PID" 2>/dev/null; then
      log "Process still alive — sending SIGKILL..."
      kill -9 "$PID" 2>/dev/null || true
    fi
    STOPPED=true
  else
    log "PID $PID from .admin.pid is no longer running"
  fi
  rm -f "$PID_FILE"
fi

# Fallback: kill anything on port 4200
PORT_PIDS=$(lsof -ti:4200 2>/dev/null || true)
if [[ -n "$PORT_PIDS" ]]; then
  log "Killing processes on port 4200: $PORT_PIDS"
  echo "$PORT_PIDS" | xargs kill -9 2>/dev/null || true
  STOPPED=true
fi

$STOPPED && log "✓ Admin UI stopped" || log "✓ Admin UI was not running"

echo ""
log "Admin UI shutdown complete."
