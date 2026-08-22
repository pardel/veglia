# Uptime over a range, reported alongside the coverage that earns it.
#
# The two numbers are kept apart on purpose. Uptime answers "of the
# minutes we watched, how many were connected"; coverage answers "how
# many minutes did we watch at all". Blending them produces the
# reassuring fiction this whole application exists to avoid, because a
# monitor that was switched off for a day would otherwise report a
# flawless day.
class Stats
  def self.window(node:, window:, now: Time.current)
    new(node: node, from: now - window, to: now)
  end

  def self.day(node:, day:)
    new(node: node, from: day.beginning_of_day, to: day.end_of_day)
  end

  def initialize(node:, from:, to:)
    @node = node
    @from = from
    @to = to
  end

  def expected_minutes = ((to - from) / 60).round

  def observed_minutes = counts.values.sum

  def up_minutes = counts.fetch(Check::UP, 0)

  def degraded_minutes = counts.fetch(Check::DEGRADED, 0)

  def down_minutes = Check::OUTAGES.sum { counts.fetch(_1, 0) }

  # A hole in a record that had already started: Veglia was installed
  # and was supposed to be writing rows, and did not. That is a failure
  # of the monitor, and the dashboard colours it as one.
  def missing_minutes = [ expected_minutes - observed_minutes - unstarted_minutes, 0 ].max

  # Minutes in the window that predate this node's first check. Nothing
  # was watching because nothing had been installed yet, so they are not
  # anyone's fault and must not be dressed as one — a 30-day window on a
  # day-old node is mostly this, and colouring it as failure would be
  # the same lie as the old grey, told the other way round.
  def unstarted_minutes
    return expected_minutes if first_checked_at.nil?
    return 0 if first_checked_at <= from

    (([ first_checked_at, to ].min - from) / 60).round.clamp(0, expected_minutes)
  end

  def uptime_percent
    return nil if observed_minutes.zero?
    (up_minutes + degraded_minutes) * 100.0 / observed_minutes
  end

  def coverage_percent
    return nil if expected_minutes.zero?
    [ observed_minutes * 100.0 / expected_minutes, 100.0 ].min
  end

  def p50_ms = percentile(50)
  def p95_ms = percentile(95)

  private

  attr_reader :node, :from, :to

  def scope = Check.for_node(node).where(checked_at: from..to)

  # Memoised through `defined?` rather than `||=`: the answer is
  # legitimately nil on a node that has never checked.
  def first_checked_at
    return @first_checked_at if defined?(@first_checked_at)
    @first_checked_at = Check.for_node(node).minimum(:checked_at)
  end

  def counts = @counts ||= scope.group(:status).count

  def latencies
    @latencies ||= scope.where.not(http_ms: nil).order(:http_ms).pluck(:http_ms)
  end

  def percentile(pct)
    return nil if latencies.empty?
    index = ((pct / 100.0) * (latencies.size - 1)).round
    latencies[index]
  end
end
