class AddEstimateItemsCountToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :estimate_items_count, :integer, default: 0, null: false

    # Reset counter cache for existing records
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE estimates
          SET estimate_items_count = (
            SELECT COUNT(*) FROM estimate_items
            WHERE estimate_items.estimate_id = estimates.id
          )
        SQL
      end
    end
  end
end
