class DailyStat < ApplicationRecord
  scope :for_node, ->(node) { where(node: node) }
  scope :recent,   -> { order(day: :desc) }

  # Of the minutes we actually watched, how many were connected.
  def uptime_percent
    return nil if observed_minutes.zero?
    (up_minutes + degraded_minutes) * 100.0 / observed_minutes
  end

  # How many of the day's minutes we watched at all. Reported beside
  # uptime, never folded into it.
  def coverage_percent
    return nil if expected_minutes.zero?
    observed_minutes * 100.0 / expected_minutes
  end
end
