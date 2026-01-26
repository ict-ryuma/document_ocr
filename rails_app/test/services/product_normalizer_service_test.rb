# frozen_string_literal: true

require "test_helper"

class ProductNormalizerServiceTest < ActiveSupport::TestCase
  test "normalize returns wiper_blade for ワイパー" do
    assert_equal "wiper_blade", ProductNormalizerService.normalize("ワイパー")
  end

  test "normalize returns wiper_blade for ワイパーブレード" do
    assert_equal "wiper_blade", ProductNormalizerService.normalize("ワイパーブレード")
  end

  test "normalize returns engine_oil for エンジンオイル" do
    assert_equal "engine_oil", ProductNormalizerService.normalize("エンジンオイル 5W-30")
  end

  test "normalize returns battery for バッテリー" do
    assert_equal "battery", ProductNormalizerService.normalize("バッテリー交換")
  end

  test "normalize returns unknown for empty string" do
    assert_equal "unknown", ProductNormalizerService.normalize("")
  end

  test "normalize returns unknown for nil" do
    assert_equal "unknown", ProductNormalizerService.normalize(nil)
  end

  test "determine_cost_type returns labor for 工賃" do
    assert_equal "labor", ProductNormalizerService.determine_cost_type("オイル交換工賃")
  end

  test "determine_cost_type returns labor for 作業" do
    assert_equal "labor", ProductNormalizerService.determine_cost_type("点検作業")
  end

  test "determine_cost_type returns parts for regular items" do
    assert_equal "parts", ProductNormalizerService.determine_cost_type("エンジンオイル")
  end

  test "determine_cost_type returns parts for nil" do
    assert_equal "parts", ProductNormalizerService.determine_cost_type(nil)
  end

  test "process_items adds item_name_norm and cost_type" do
    items = [
      { item_name_raw: "ワイパーブレード", amount_excl_tax: 3000 },
      { item_name_raw: "交換工賃", amount_excl_tax: 1500 }
    ]

    result = ProductNormalizerService.process_items(items)

    assert_equal "wiper_blade", result[0][:item_name_norm]
    assert_equal "parts", result[0][:cost_type]
    assert_equal "labor", result[1][:cost_type]
  end

  test "process_items prefers item_name_corrected over item_name_raw" do
    items = [
      { item_name_raw: "ワイパ一ブレ一ド", item_name_corrected: "ワイパーブレード", amount_excl_tax: 3000 }
    ]

    result = ProductNormalizerService.process_items(items)

    assert_equal "wiper_blade", result[0][:item_name_norm]
    assert_equal "parts", result[0][:cost_type]
  end

  test "process_items falls back to item_name_raw when item_name_corrected is nil" do
    items = [
      { item_name_raw: "エンジンオイル", item_name_corrected: nil, amount_excl_tax: 5000 }
    ]

    result = ProductNormalizerService.process_items(items)

    assert_equal "engine_oil", result[0][:item_name_norm]
  end

  test "extract_quantity returns 1 for no quantity pattern" do
    assert_equal 1, ProductNormalizerService.extract_quantity("エンジンオイル")
  end

  test "extract_quantity extracts from x2 pattern" do
    assert_equal 2, ProductNormalizerService.extract_quantity("ワイパー x2")
  end

  test "extract_quantity extracts from 3個 pattern" do
    assert_equal 3, ProductNormalizerService.extract_quantity("ボルト 3個")
  end
end
