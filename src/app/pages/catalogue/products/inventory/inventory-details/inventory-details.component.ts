import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { InventoryService } from '../../services/inventory.service';
import { ProductService } from '../../services/product.service';
import { Location } from '@angular/common';

@Component({
  selector: 'ngx-inventory-details',
  templateUrl: './inventory-details.component.html',
  styleUrls: ['./inventory-details.component.scss'],
})
export class InventoryDetailsComponent implements OnInit {
  inventory = {};

  constructor(
    private activatedRoute: ActivatedRoute,
    private inventoryService: InventoryService,
    private productService: ProductService,
    private router: Router,
    private location: Location,
  ) {
    let productId = this.activatedRoute.snapshot.paramMap.get('productId');
    if (!productId) {
      productId = this.productService.getProductIdRoute(this.router, this.location);
    }
    const inventoryId = this.activatedRoute.snapshot.paramMap.get('inventoryId');
    this.inventoryService.getInventoryById(productId, inventoryId).subscribe((res) => {
      this.inventory = { ...res };
    });
  }

  ngOnInit() {
  }

}
