class EstimatePriceQuery
  def initialize(item_name_norm)
    @item_name_norm = item_name_norm
  end

  # Alias for compatibility with controllers calling .execute
  def execute
    call
  end

  def call
    items = EstimateItem.where(item_name_norm: @item_name_norm)
    return { error: "No items found for #{@item_name_norm}" } if items.empty?

    estimate_ids = items.pluck(:estimate_id).uniq
    estimates = Estimate.where(id: estimate_ids)

    single_vendor_best = calculate_single_vendor_best(items, estimates)
    split_best = calculate_split_best(items)
    totals_per_estimate = calculate_totals_per_estimate(items, estimates)

    {
      single_vendor_best: single_vendor_best,
      split_theoretical_best: split_best,
      totals_per_estimate: totals_per_estimate
    }
  end

  private

  def calculate_single_vendor_best(items, estimates)
    grouped = items.group_by(&:estimate_id)
    best = grouped.map do |estimate_id, est_items|
      total = est_items.sum(&:amount_excl_tax)
      estimate = estimates.find { |e| e.id == estimate_id }
      {
        estimate_id: estimate_id,
        vendor_name: estimate&.vendor_name,
        total: total
      }
    end.min_by { |x| x[:total] }

    best
  end

  def calculate_split_best(items)
    parts_items = items.where(cost_type: 'parts')
    labor_items = items.where(cost_type: 'labor')

    parts_min = parts_items.minimum(:amount_excl_tax) || 0
    labor_min = labor_items.minimum(:amount_excl_tax) || 0

    {
      parts_min: parts_min,
      labor_min: labor_min,
      total: parts_min + labor_min
    }
  end

  def calculate_totals_per_estimate(items, estimates)
    grouped = items.group_by(&:estimate_id)
    totals = grouped.map do |estimate_id, est_items|
      total = est_items.sum(&:amount_excl_tax)
      estimate = estimates.find { |e| e.id == estimate_id }
      {
        estimate_id: estimate_id,
        vendor_name: estimate&.vendor_name,
        total: total
      }
    end

    totals.sort_by { |x| x[:total] }
  end
end