# frozen_string_literal: true

require "test_helper"

class EstimateTest < ActiveSupport::TestCase
  test "valid estimate with all required fields" do
    estimate = Estimate.new(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )
    assert estimate.valid?
  end

  test "invalid without vendor_name" do
    estimate = Estimate.new(
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )
    assert_not estimate.valid?
    assert_includes estimate.errors[:vendor_name], "can't be blank"
  end

  test "invalid without estimate_date" do
    estimate = Estimate.new(
      vendor_name: "Test Vendor",
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )
    assert_not estimate.valid?
    assert_includes estimate.errors[:estimate_date], "can't be blank"
  end

  test "invalid with negative total_excl_tax" do
    estimate = Estimate.new(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: -100,
      total_incl_tax: 11000
    )
    assert_not estimate.valid?
  end

  test "items_count returns correct count" do
    estimate = Estimate.create!(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )

    estimate.estimate_items.create!(
      item_name_raw: "Test Item",
      item_name_norm: "test_item",
      cost_type: "parts",
      amount_excl_tax: 5000
    )

    assert_equal 1, estimate.items_count
  end

  test "has_many estimate_items association" do
    estimate = Estimate.new
    assert_respond_to estimate, :estimate_items
  end

  test "destroys associated estimate_items on delete" do
    estimate = Estimate.create!(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )

    estimate.estimate_items.create!(
      item_name_raw: "Test Item",
      item_name_norm: "test_item",
      cost_type: "parts",
      amount_excl_tax: 5000
    )

    assert_difference "EstimateItem.count", -1 do
      estimate.destroy
    end
  end
end
