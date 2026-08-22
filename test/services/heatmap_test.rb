require "test_helper"

class HeatmapTest < ActiveSupport::TestCase
  NODE = "testnode".freeze

  test "a 24 hour window is 288 five-minute buckets" do
    assert_equal 288, Heatmap.new(node: NODE).buckets.size
  end

  test "a node that has never checked is unstarted, not missing and not up" do
    # Nothing was ever promised for these minutes, so they are neither a
    # green day nor a day of failure.
    buckets = Heatmap.new(node: NODE).buckets

    assert buckets.all? { _1.status == Heatmap::UNSTARTED }
    assert buckets.all? { _1.count.zero? }
  end

  test "a hole after the record starts is missing, not up and not unstarted" do
    now = Time.current
    Check.create!(node: NODE, checked_at: now - 3.hours, status: Check::UP, boot_at: 1.day.ago)
    Check.create!(node: NODE, checked_at: now - 1.minute, status: Check::UP, boot_at: 1.day.ago)

    buckets = Heatmap.new(node: NODE, now: now).buckets
    gap = buckets.select { _1.count.zero? && _1.starts_at > now - 3.hours }

    assert gap.any?
    assert gap.all? { _1.status == Heatmap::MISSING }
  end

  test "minutes before the first check stay unstarted even once checks exist" do
    now = Time.current
    Check.create!(node: NODE, checked_at: now - 1.minute, status: Check::UP, boot_at: 1.day.ago)

    buckets = Heatmap.new(node: NODE, now: now).buckets

    assert_equal Heatmap::UNSTARTED, buckets.first.status
  end

  test "the worst status in a bucket wins" do
    # Four good minutes and one bad one share a bucket. Showing green
    # would hide the only thing worth seeing.
    now = Time.current
    base = Time.zone.at((now.to_i / Heatmap::BUCKET_SECONDS) * Heatmap::BUCKET_SECONDS) - 10.minutes

    4.times { |i| Check.create!(node: NODE, checked_at: base + i.minutes, status: Check::UP, boot_at: 1.day.ago) }
    Check.create!(node: NODE, checked_at: base + 4.minutes, status: Check::LAN_DOWN, boot_at: 1.day.ago)

    bucket = Heatmap.new(node: NODE, now: now).buckets.find { _1.starts_at.to_i == base.to_i }

    assert_not_nil bucket
    assert_equal Check::LAN_DOWN, bucket.status
    assert_equal 5, bucket.count
  end

  test "degraded does not mask a genuine outage in the same bucket" do
    now = Time.current
    base = Time.zone.at((now.to_i / Heatmap::BUCKET_SECONDS) * Heatmap::BUCKET_SECONDS) - 10.minutes

    Check.create!(node: NODE, checked_at: base, status: Check::DEGRADED, boot_at: 1.day.ago)
    Check.create!(node: NODE, checked_at: base + 1.minute, status: Check::INTERNET_DOWN, boot_at: 1.day.ago)

    bucket = Heatmap.new(node: NODE, now: now).buckets.find { _1.starts_at.to_i == base.to_i }

    assert_equal Check::INTERNET_DOWN, bucket.status
  end

  test "another node's checks do not appear in this node's strip" do
    now = Time.current
    Check.create!(node: "elsewhere", checked_at: now - 5.minutes, status: Check::UP, boot_at: 1.day.ago)

    buckets = Heatmap.new(node: NODE, now: now).buckets
    assert buckets.all? { _1.count.zero? }
    assert buckets.none? { _1.status == Check::UP }
  end
end
