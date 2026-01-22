class Estimate < ApplicationRecord
  has_many :estimate_items, dependent: :destroy

  validates :vendor_name, presence: true
  validates :estimate_date, presence: true
  validates :total_excl_tax, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_incl_tax, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def items_count
    # Use size instead of count to leverage preloaded associations
    # count always hits DB, size uses loaded records if available
    estimate_items.size
  end

  def as_json(options = {})
    super(options.merge(methods: [ :items_count ]))
  end
end
