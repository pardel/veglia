# Turns a hole in the record into a stated fact.
#
# This is the piece that stops Veglia flattering itself. A monitor
# cannot write a row while it is not running, so its own downtime looks
# exactly like a quiet, healthy stretch unless something goes looking
# for the absence. Every check therefore begins by asking how long it
# has been since the last one.
#
# The kernel boot time tells the two causes apart. If the machine came
# up in the meantime, the hole belongs to the machine; if it did not,
# the machine was fine and Veglia was the thing that was missing.
class GapDetector
  def initialize(node:, previous:, boot_at:, now:)
    @node = node
    @previous = previous
    @boot_at = boot_at
    @now = now
  end

  def call
    return [] if previous.nil?

    elapsed = now - previous.checked_at
    return [] if elapsed <= Settings.gap_threshold_seconds

    rebooted? ? reboot_outages : [ record(Outage::APP_GAP, previous.checked_at, now) ]
  end

  private

  attr_reader :node, :previous, :boot_at, :now

  def rebooted?
    return false if boot_at.nil? || previous.boot_at.nil?
    # A few seconds of slack: the reported boot time can wobble slightly
    # between reads without the machine having gone anywhere.
    boot_at > previous.boot_at + 5.seconds
  end

  # A reboot is two different absences back to back, and saying so is
  # more useful than one undifferentiated blob: the machine was off
  # until it booted, and then Veglia took a while to come back.
  def reboot_outages
    outages = [ record(Outage::MACHINE_REBOOT, previous.checked_at, boot_at) ]

    startup_delay = now - boot_at
    if startup_delay > Settings.gap_threshold_seconds
      outages << record(Outage::APP_GAP, boot_at, now, "machine was up; Veglia had not started")
    end

    outages
  end

  # Idempotent by way of the unique index on (node, kind, started_at).
  #
  # CheckRunner reads the last stored check and then asks about the gap
  # before it, with nothing between the read and the write, so two runs
  # that overlap both see the same stale predecessor and both conclude
  # the same hole preceded it. That is not hypothetical: on recovery the
  # scheduler releases the minutes it banked while the app was down, the
  # worker's three threads take three of them at once, and the gap gets
  # written three times. The database decides which one is the record.
  def record(kind, started_at, ended_at, detail = nil)
    Outage.create!(
      node: node,
      kind: kind,
      started_at: started_at,
      ended_at: ended_at,
      duration_s: (ended_at - started_at).round,
      detail: detail
    )
  rescue ActiveRecord::RecordNotUnique
    Outage.find_by(node: node, kind: kind, started_at: started_at)
  end
end
