require "test_helper"

# The heart of the honesty guarantee: these tests assert that Veglia
# accounts for the time it was not watching, and attributes it to the
# right cause.
class GapDetectorTest < ActiveSupport::TestCase
  NODE = "testnode".freeze

  def previous_check(checked_at:, boot_at:)
    Check.create!(node: NODE, checked_at: checked_at, status: Check::UP, boot_at: boot_at)
  end

  # The bug this pins: on recovery the scheduler releases the minutes it
  # banked while the app was down, three worker threads take three of
  # them at once, and all three see the same stale predecessor. The live
  # database held 41 rows for 20 spans before the unique index went on.
  test "concurrent runs detecting the same hole record it once" do
    boot = 3.days.ago
    now = Time.current
    previous = previous_check(checked_at: now - 20.minutes, boot_at: boot)

    3.times do
      GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call
    end

    assert_equal 1, Outage.where(node: NODE, kind: Outage::APP_GAP).count,
                 "one hole in the record is one row, however many runs noticed it"
  end

  test "a repeat detection returns the existing row rather than nil" do
    boot = 3.days.ago
    now = Time.current
    previous = previous_check(checked_at: now - 20.minutes, boot_at: boot)

    first = GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call
    again = GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call

    assert_equal first.map(&:id), again.map(&:id)
  end

  test "no previous check means nothing to infer" do
    outages = GapDetector.new(node: NODE, previous: nil, boot_at: Time.current, now: Time.current).call
    assert_empty outages
  end

  test "a check on schedule records no gap" do
    boot = 3.days.ago
    now = Time.current
    previous = previous_check(checked_at: now - 60.seconds, boot_at: boot)

    outages = GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call

    assert_empty outages
    assert_equal 0, Outage.count
  end

  test "a late-but-tolerable check records no gap" do
    boot = 3.days.ago
    now = Time.current
    previous = previous_check(checked_at: now - 89.seconds, boot_at: boot)

    assert_empty GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call
  end

  test "a hole with an unchanged boot time is the app's own absence" do
    boot = 3.days.ago
    now = Time.current
    previous = previous_check(checked_at: now - 10.minutes, boot_at: boot)

    outages = GapDetector.new(node: NODE, previous: previous, boot_at: boot, now: now).call

    assert_equal 1, outages.size
    outage = outages.first
    assert_equal Outage::APP_GAP, outage.kind
    assert_in_delta 600, outage.duration_s, 1
    assert_equal previous.checked_at.to_i, outage.started_at.to_i
  end

  test "a hole spanning a new boot time is the machine's downtime" do
    old_boot = 3.days.ago
    now = Time.current
    # The machine was off for twenty minutes, then booted one minute ago.
    new_boot = now - 1.minute
    previous = previous_check(checked_at: now - 21.minutes, boot_at: old_boot)

    outages = GapDetector.new(node: NODE, previous: previous, boot_at: new_boot, now: now).call

    assert_equal 1, outages.size
    assert_equal Outage::MACHINE_REBOOT, outages.first.kind
    # The machine's downtime ends when it booted, not when Veglia noticed.
    assert_equal new_boot.to_i, outages.first.ended_at.to_i
    assert_in_delta 20.minutes, outages.first.duration_s, 1
  end

  test "a slow start after a reboot is recorded separately from the reboot" do
    old_boot = 3.days.ago
    now = Time.current
    # Booted ten minutes ago but Veglia has only just started checking.
    new_boot = now - 10.minutes
    previous = previous_check(checked_at: now - 30.minutes, boot_at: old_boot)

    outages = GapDetector.new(node: NODE, previous: previous, boot_at: new_boot, now: now).call

    assert_equal 2, outages.size
    assert_equal [ Outage::MACHINE_REBOOT, Outage::APP_GAP ], outages.map(&:kind)
    assert_in_delta 20.minutes, outages.first.duration_s, 1
    assert_in_delta 10.minutes, outages.last.duration_s, 1
  end

  test "an unknown boot time falls back to blaming the app, not the machine" do
    now = Time.current
    previous = previous_check(checked_at: now - 10.minutes, boot_at: nil)

    outages = GapDetector.new(node: NODE, previous: previous, boot_at: nil, now: now).call

    assert_equal Outage::APP_GAP, outages.first.kind
  end
end
