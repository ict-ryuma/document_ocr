class CreateEstimates < ActiveRecord::Migration[7.1]
  def change
    create_table :estimates do |t|
      t.string :vendor_name
      t.date :estimate_date
      t.integer :total_excl_tax
      t.integer :total_incl_tax

      t.timestamps
    end

    add_index :estimates, :vendor_name
    add_index :estimates, :estimate_date
  end
end
