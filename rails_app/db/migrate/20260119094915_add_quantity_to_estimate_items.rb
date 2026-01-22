class AddQuantityToEstimateItems < ActiveRecord::Migration[8.0]
  def change
    add_column :estimate_items, :quantity, :integer, default: 1, null: false
  end
end
