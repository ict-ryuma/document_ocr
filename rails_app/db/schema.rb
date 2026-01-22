# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_22_003317) do
  create_table "estimate_items", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "amount_excl_tax"
    t.string "cost_type"
    t.datetime "created_at", null: false
    t.bigint "estimate_id", null: false
    t.string "item_name_norm"
    t.string "item_name_raw"
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["cost_type"], name: "index_estimate_items_on_cost_type"
    t.index ["estimate_id"], name: "index_estimate_items_on_estimate_id"
    t.index ["item_name_norm"], name: "index_estimate_items_on_item_name_norm"
  end

  create_table "estimates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "ai_analysis", comment: "Azure OpenAI分析結果（JSON形式）"
    t.datetime "created_at", null: false
    t.date "estimate_date"
    t.string "kintone_record_id", comment: "kintoneレコードID"
    t.integer "total_excl_tax"
    t.integer "total_incl_tax"
    t.datetime "updated_at", null: false
    t.string "vendor_address"
    t.string "vendor_name"
    t.index ["estimate_date"], name: "index_estimates_on_estimate_date"
    t.index ["kintone_record_id"], name: "index_estimates_on_kintone_record_id"
    t.index ["vendor_name"], name: "index_estimates_on_vendor_name"
  end

  add_foreign_key "estimate_items", "estimates"
end
