# Collapses a run of failing checks into one outage with a start and an
# end, so the dashboard can say "the internet was down for 14 minutes"
# rather than showing fourteen red dots and leaving the arithmetic to
# the reader.
#
# Only observed failures are handled here. Gaps are Outage records too,
# but they are created by GapDetector, already closed, and must never
# be reopened by this class.
class OutageTracker
  def initialize(check)
    @check = check
  end

  def call
    if check.down?
      current_outage_matching || start_outage
    else
      close_open_outage
    end
  end

  private

  attr_reader :check

  def open_outage
    @open_outage ||= Outage.for_node(check.node).observed.open.order(:started_at).last
  end

  # A failure of the same kind continues the existing outage. A failure
  # of a *different* kind ends one and begins another: DNS recovering
  # into a full internet outage is two facts, not one.
  def current_outage_matching
    return nil unless open_outage
    return open_outage if open_outage.kind == check.status

    close(open_outage)
    start_outage
  end

  def start_outage
    Outage.create!(node: check.node, kind: check.status, started_at: check.checked_at)
  end

  def close_open_outage
    close(open_outage) if open_outage
  end

  def close(outage)
    outage.update!(ended_at: check.checked_at, duration_s: (check.checked_at - outage.started_at).round)
  end
end
