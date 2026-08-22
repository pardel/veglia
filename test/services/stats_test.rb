require "test_helper"

# These tests exist to stop the one lie Veglia must never tell: a high
# uptime figure derived from a handful of observed minutes, presented as
# though it described the whole window.
class StatsTest < ActiveSupport::TestCase
  NODE = "testnode".freeze

  def fill(minutes:, status: Check::UP, ending_at: Time.current)
    minutes.times do |i|
      Check.create!(node: NODE, checked_at: ending_at - i.minutes, status: status,
                    boot_at: 3.days.ago, http_ms: 40.0 + i)
    end
  end

  test "a fully observed healthy hour is 100% up at 100% coverage" do
    now = Time.current
    fill(minutes: 60, ending_at: now - 1.second)

    stats = Stats.window(node: NODE, window: 1.hour, now: now)

    assert_equal 60, stats.expected_minutes
    assert_equal 60, stats.observed_minutes
    assert_in_delta 100.0, stats.uptime_percent, 0.01
    assert_in_delta 100.0, stats.coverage_percent, 0.01
    assert_equal 0, stats.missing_minutes
  end

  test "unobserved minutes reduce coverage and never inflate uptime" do
    now = Time.current
    # Only ten of the hour's sixty minutes were watched, and the node had
    # been running well before the window opened, so the other fifty are
    # a hole Veglia left rather than time that predates it.
    Check.create!(node: NODE, checked_at: now - 2.hours, status: Check::UP, boot_at: 3.days.ago)
    fill(minutes: 10, ending_at: now - 1.second)

    stats = Stats.window(node: NODE, window: 1.hour, now: now)

    assert_in_delta 100.0, stats.uptime_percent, 0.01, "of what was seen, all was up"
    assert_in_delta 16.67, stats.coverage_percent, 0.05, "but only a sixth was seen"
    assert_equal 50, stats.missing_minutes
    assert_equal 0, stats.unstarted_minutes
  end

  test "minutes before the node's first check are not counted as a failure" do
    now = Time.current
    # A node ten minutes old, asked about the last hour. The fifty
    # minutes before it existed are nobody's fault, and billing them as
    # unobserved would be the old grey's lie told the other way round.
    fill(minutes: 10, ending_at: now - 1.second)

    stats = Stats.window(node: NODE, window: 1.hour, now: now)

    assert_equal 0, stats.missing_minutes, "nothing was watching because nothing was installed"
    assert_in_delta 51, stats.unstarted_minutes, 1
    assert_in_delta 16.67, stats.coverage_percent, 0.05, "coverage still reports the whole window"
  end

  test "downtime lowers uptime while coverage stays whole" do
    now = Time.current
    fill(minutes: 45, status: Check::UP, ending_at: now - 1.second)
    fill(minutes: 15, status: Check::INTERNET_DOWN, ending_at: now - 46.minutes)

    stats = Stats.window(node: NODE, window: 1.hour, now: now)

    assert_equal 60, stats.observed_minutes
    assert_equal 15, stats.down_minutes
    assert_in_delta 75.0, stats.uptime_percent, 0.01
    assert_in_delta 100.0, stats.coverage_percent, 0.01
  end

  test "degraded minutes count as connected but are reported separately" do
    now = Time.current
    fill(minutes: 30, status: Check::UP, ending_at: now - 1.second)
    fill(minutes: 30, status: Check::DEGRADED, ending_at: now - 31.minutes)

    stats = Stats.window(node: NODE, window: 1.hour, now: now)

    assert_in_delta 100.0, stats.uptime_percent, 0.01
    assert_equal 30, stats.degraded_minutes
    assert_equal 0, stats.down_minutes
  end

  test "a window with nothing in it reports no uptime rather than zero or full" do
    stats = Stats.window(node: NODE, window: 1.hour, now: Time.current)

    assert_nil stats.uptime_percent, "an unknown figure must not render as 0% or 100%"
    assert_in_delta 0.0, stats.coverage_percent, 0.01
    assert_equal 0, stats.missing_minutes, "a node that never ran left no hole to blame it for"
    assert_equal 60, stats.unstarted_minutes
  end

  test "latency percentiles come from observed checks only" do
    now = Time.current
    fill(minutes: 100, ending_at: now - 1.second)

    stats = Stats.window(node: NODE, window: 2.hours, now: now)

    assert_not_nil stats.p50_ms
    assert_operator stats.p95_ms, :>=, stats.p50_ms
  end
end
