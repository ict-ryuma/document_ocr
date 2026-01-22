#!/usr/bin/env ruby

require_relative '../config/environment'

ActiveRecord::Base.transaction do
  # Create Estimate #1
  estimate1 = Estimate.create!(
    vendor_name: 'AutoShop A',
    estimate_date: Date.parse('2025-01-15'),
    total_excl_tax: 50000,
    total_incl_tax: 55000
  )

  EstimateItem.create!(
    estimate: estimate1,
    item_name_raw: 'ワイパーブレード',
    item_name_norm: 'wiper_blade',
    cost_type: 'parts',
    amount_excl_tax: 3500
  )

  EstimateItem.create!(
    estimate: estimate1,
    item_name_raw: 'ワイパー交換工賃',
    item_name_norm: 'wiper_blade',
    cost_type: 'labor',
    amount_excl_tax: 2000
  )

  EstimateItem.create!(
    estimate: estimate1,
    item_name_raw: 'エンジンオイル',
    item_name_norm: 'engine_oil',
    cost_type: 'parts',
    amount_excl_tax: 4500
  )

  EstimateItem.create!(
    estimate: estimate1,
    item_name_raw: 'オイル交換工賃',
    item_name_norm: 'engine_oil',
    cost_type: 'labor',
    amount_excl_tax: 1500
  )

  # Create Estimate #2
  estimate2 = Estimate.create!(
    vendor_name: 'AutoShop B',
    estimate_date: Date.parse('2025-01-16'),
    total_excl_tax: 52000,
    total_incl_tax: 57200
  )

  EstimateItem.create!(
    estimate: estimate2,
    item_name_raw: 'Wiper Blade Premium',
    item_name_norm: 'wiper_blade',
    cost_type: 'parts',
    amount_excl_tax: 4200
  )

  EstimateItem.create!(
    estimate: estimate2,
    item_name_raw: 'Wiper installation labor',
    item_name_norm: 'wiper_blade',
    cost_type: 'labor',
    amount_excl_tax: 2500
  )

  EstimateItem.create!(
    estimate: estimate2,
    item_name_raw: 'Synthetic Engine Oil',
    item_name_norm: 'engine_oil',
    cost_type: 'parts',
    amount_excl_tax: 5800
  )

  EstimateItem.create!(
    estimate: estimate2,
    item_name_raw: 'Oil change service',
    item_name_norm: 'engine_oil',
    cost_type: 'labor',
    amount_excl_tax: 1800
  )

  puts "✓ Created 2 estimates with items"
  puts "  Estimate #1 (AutoShop A): #{estimate1.estimate_items.count} items"
  puts "  Estimate #2 (AutoShop B): #{estimate2.estimate_items.count} items"
end