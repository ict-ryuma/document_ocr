class EstimateItem < ApplicationRecord
  belongs_to :estimate, counter_cache: true

  validates :item_name_raw, presence: true
  validates :item_name_norm, presence: true
  validates :cost_type, presence: true, inclusion: { in: %w[parts labor] }
  validates :amount_excl_tax, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :by_normalized_item, ->(item_name) { where(item_name_norm: item_name) }
  scope :parts_only, -> { where(cost_type: "parts") }
  scope :labor_only, -> { where(cost_type: "labor") }
end
