# Nightly: freeze each completed day into a DailyStat, then drop raw
# checks past the retention window.
#
# The order is not incidental. Pruning before rolling up would destroy
# the history it summarises, so the roll-up always runs first and the
# prune only ever removes days that have already been summarised.
class Rollup
  def self.call(now: Time.current) = new(now: now).call

  def initialize(now: Time.current)
    @now = now
  end

  def call
    Check.nodes.each { roll_up_node(_1) }
    prune
  end

  private

  attr_reader :now

  def roll_up_node(node)
    earliest = Check.for_node(node).minimum(:checked_at)
    return if earliest.nil?

    first_day = earliest.in_time_zone.to_date
    # Only completed days. Today is still accumulating, and a partial
    # day frozen into the record would understate its own coverage.
    last_day = now.to_date - 1
    return if last_day < first_day

    (first_day..last_day).each do |day|
      next if DailyStat.for_node(node).exists?(day: day)
      store(node, day)
    end
  end

  def store(node, day)
    stats = Stats.day(node: node, day: day)

    DailyStat.create!(
      node: node,
      day: day,
      expected_minutes: stats.expected_minutes,
      observed_minutes: stats.observed_minutes,
      up_minutes: stats.up_minutes,
      degraded_minutes: stats.degraded_minutes,
      down_minutes: stats.down_minutes,
      p50_ms: stats.p50_ms,
      p95_ms: stats.p95_ms
    )
  rescue ActiveRecord::RecordNotUnique
    # Two runs raced. The day is already recorded, which is the point.
    nil
  end

  def prune
    cutoff = now - Settings.retention_days.days
    Check.where(checked_at: ...cutoff).delete_all
    # Outages are the compressed form and cost almost nothing, so they
    # outlive the raw checks they were derived from.
  end
end
