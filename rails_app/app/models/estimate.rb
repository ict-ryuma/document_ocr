class Estimate < ApplicationRecord
  has_many :estimate_items, dependent: :destroy

  validates :vendor_name, presence: true
  validates :estimate_date, presence: true
  validates :total_excl_tax, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_incl_tax, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def items_count
    # Use counter cache column for optimal performance
    estimate_items_count
  end

  def as_json(options = {})
    super(options.merge(methods: [ :items_count ]))
  end
end
