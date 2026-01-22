class AddVendorAddressToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :vendor_address, :string
  end
end
