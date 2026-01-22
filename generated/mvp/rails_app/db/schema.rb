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

ActiveRecord::Schema[7.1].define(version: 2024_01_15_000002) do
  create_table "estimates", force: :cascade do |t|
    t.string "vendor_name"
    t.date "estimate_date"
    t.integer "total_excl_tax"
    t.integer "total_incl_tax"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "estimate_items", force: :cascade do |t|
    t.integer "estimate_id", null: false
    t.string "item_name_raw"
    t.string "item_name_norm"
    t.string "cost_type"
    t.integer "amount_excl_tax"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["estimate_id"], name: "index_estimate_items_on_estimate_id"
    t.index ["item_name_norm"], name: "index_estimate_items_on_item_name_norm"
  end

  add_foreign_key "estimate_items", "estimates"
end
