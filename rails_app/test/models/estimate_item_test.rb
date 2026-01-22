# frozen_string_literal: true

require "test_helper"

class EstimateItemTest < ActiveSupport::TestCase
  setup do
    @estimate = Estimate.create!(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )
  end

  test "valid estimate item with all required fields" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_raw: "ワイパーブレード",
      item_name_norm: "wiper_blade",
      cost_type: "parts",
      amount_excl_tax: 3000
    )
    assert item.valid?
  end

  test "invalid without item_name_raw" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_norm: "wiper_blade",
      cost_type: "parts",
      amount_excl_tax: 3000
    )
    assert_not item.valid?
    assert_includes item.errors[:item_name_raw], "can't be blank"
  end

  test "invalid without item_name_norm" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_raw: "ワイパーブレード",
      cost_type: "parts",
      amount_excl_tax: 3000
    )
    assert_not item.valid?
    assert_includes item.errors[:item_name_norm], "can't be blank"
  end

  test "invalid with unknown cost_type" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_raw: "ワイパーブレード",
      item_name_norm: "wiper_blade",
      cost_type: "unknown",
      amount_excl_tax: 3000
    )
    assert_not item.valid?
    assert_includes item.errors[:cost_type], "is not included in the list"
  end

  test "cost_type must be parts or labor" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_raw: "Test",
      item_name_norm: "test",
      cost_type: "parts",
      amount_excl_tax: 1000
    )
    assert item.valid?

    item.cost_type = "labor"
    assert item.valid?
  end

  test "invalid with negative amount_excl_tax" do
    item = EstimateItem.new(
      estimate: @estimate,
      item_name_raw: "Test",
      item_name_norm: "test",
      cost_type: "parts",
      amount_excl_tax: -100
    )
    assert_not item.valid?
  end

  test "parts_only scope returns only parts" do
    @estimate.estimate_items.create!(
      item_name_raw: "Part",
      item_name_norm: "part",
      cost_type: "parts",
      amount_excl_tax: 1000
    )
    @estimate.estimate_items.create!(
      item_name_raw: "Labor",
      item_name_norm: "labor",
      cost_type: "labor",
      amount_excl_tax: 500
    )

    parts = EstimateItem.parts_only
    assert parts.all? { |item| item.cost_type == "parts" }
  end

  test "labor_only scope returns only labor" do
    @estimate.estimate_items.create!(
      item_name_raw: "Part",
      item_name_norm: "part",
      cost_type: "parts",
      amount_excl_tax: 1000
    )
    @estimate.estimate_items.create!(
      item_name_raw: "Labor",
      item_name_norm: "labor",
      cost_type: "labor",
      amount_excl_tax: 500
    )

    labor = EstimateItem.labor_only
    assert labor.all? { |item| item.cost_type == "labor" }
  end

  test "belongs_to estimate association" do
    item = EstimateItem.new
    assert_respond_to item, :estimate
  end
end
