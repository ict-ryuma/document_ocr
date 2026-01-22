class CreateEstimateItems < ActiveRecord::Migration[7.1]
  def change
    create_table :estimate_items do |t|
      t.references :estimate, null: false, foreign_key: true
      t.string :item_name_raw
      t.string :item_name_norm
      t.string :cost_type
      t.integer :amount_excl_tax

      t.timestamps
    end

    add_index :estimate_items, :item_name_norm
    add_index :estimate_items, :cost_type
  end
end
