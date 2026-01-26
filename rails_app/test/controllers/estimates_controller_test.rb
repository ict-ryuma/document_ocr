# frozen_string_literal: true

require "test_helper"

class EstimatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @estimate = Estimate.create!(
      vendor_name: "Test Vendor",
      estimate_date: Date.current,
      total_excl_tax: 10000,
      total_incl_tax: 11000
    )

    @estimate.estimate_items.create!(
      item_name_raw: "Test Item",
      item_name_norm: "test_item",
      cost_type: "parts",
      amount_excl_tax: 10000
    )
  end

  test "should get index" do
    get estimates_url
    assert_response :success
  end

  test "should get index as JSON" do
    get estimates_url, as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_kind_of Array, json
  end

  test "should get new" do
    get new_estimate_url
    assert_response :success
  end

  test "should get show" do
    get estimate_url(@estimate)
    assert_response :success
  end

  test "should get show as JSON" do
    get estimate_url(@estimate), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @estimate.id, json["estimate"]["id"]
  end

  test "should return 404 for non-existent estimate" do
    get estimate_url(id: 999999), as: :json
    assert_response :not_found
  end

  test "create without PDF returns error" do
    post estimates_url
    assert_redirected_to new_estimate_url
    assert_equal "PDFファイルをアップロードしてください", flash[:error]
  end
end
