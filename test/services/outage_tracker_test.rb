require "test_helper"

class OutageTrackerTest < ActiveSupport::TestCase
  NODE = "testnode".freeze

  def check(status, at)
    Check.create!(node: NODE, checked_at: at, status: status, boot_at: 3.days.ago)
  end

  def track(status, at)
    c = check(status, at)
    OutageTracker.new(c).call
    c
  end

  test "a failing check opens an outage" do
    track(Check::INTERNET_DOWN, Time.current)

    outage = Outage.last
    assert_equal Outage::INTERNET_DOWN, outage.kind
    assert_nil outage.ended_at
    assert outage.ongoing?
  end

  test "consecutive failures of the same kind extend one outage" do
    start = 5.minutes.ago
    3.times { |i| track(Check::INTERNET_DOWN, start + i.minutes) }

    assert_equal 1, Outage.count
    assert_nil Outage.last.ended_at
  end

  test "recovery closes the outage with a duration" do
    start = 5.minutes.ago
    track(Check::INTERNET_DOWN, start)
    track(Check::INTERNET_DOWN, start + 1.minute)
    track(Check::UP, start + 2.minutes)

    outage = Outage.last
    assert_not_nil outage.ended_at
    assert_in_delta 120, outage.duration_s, 1
    assert_not outage.ongoing?
  end

  test "a change of failure kind ends one outage and begins another" do
    # DNS recovering into a full internet outage is two distinct facts,
    # and collapsing them would lose which one is current.
    start = 5.minutes.ago
    track(Check::DNS_DOWN, start)
    track(Check::INTERNET_DOWN, start + 1.minute)

    assert_equal 2, Outage.count
    closed, open = Outage.order(:started_at).to_a
    assert_equal Outage::DNS_DOWN, closed.kind
    assert_not_nil closed.ended_at
    assert_equal Outage::INTERNET_DOWN, open.kind
    assert_nil open.ended_at
  end

  test "degraded is not an outage" do
    track(Check::DEGRADED, Time.current)
    assert_equal 0, Outage.count
  end

  test "an inferred gap is never reopened or closed by a later check" do
    # GapDetector records gaps already closed. If OutageTracker treated
    # them as open outages it would rewrite history that was already
    # settled.
    gap = Outage.create!(node: NODE, kind: Outage::APP_GAP, started_at: 20.minutes.ago,
                         ended_at: 10.minutes.ago, duration_s: 600)

    track(Check::UP, Time.current)

    assert_equal 600, gap.reload.duration_s
    assert_equal 10.minutes.ago.to_i, gap.ended_at.to_i
  end

  test "outages are tracked per node independently" do
    other = "othernode"
    Check.create!(node: other, checked_at: Time.current, status: Check::LAN_DOWN, boot_at: 1.day.ago).then do |c|
      OutageTracker.new(c).call
    end
    track(Check::UP, Time.current)

    assert_equal 1, Outage.for_node(other).open.count
    assert_equal 0, Outage.for_node(NODE).open.count
  end
end
