# One minute's work: look for the hole before writing the row, measure,
# classify, then update the outage ledger.
#
# The gap check runs *first* and deliberately compares against the last
# stored check, because once this run's row is written the evidence of
# the absence is harder to see.
class CheckRunner
  def self.call = new.call

  def call
    node = Settings.node_name
    started_at = Time.current
    boot_at = BootTime.call

    previous = Check.for_node(node).order(:checked_at).last
    GapDetector.new(node: node, previous: previous, boot_at: boot_at, now: started_at).call

    result = Probe.call

    check = Check.create!(
      node: node,
      # Stamped at the start of the round, not the end, so rows land on
      # a steady one-minute cadence rather than drifting by however long
      # the probes took.
      checked_at: started_at,
      status: Check.classify(result),
      gateway_ok: result.gateway_ok,
      gateway_ms: result.gateway_ms,
      gateway_ip: result.gateway_ip,
      dns_ok: result.dns_ok,
      dns_ms: result.dns_ms,
      http_ok_count: result.http_ok_count,
      http_total: result.http_total,
      http_ms: result.http_ms,
      boot_at: boot_at,
      detail: result.detail
    )

    OutageTracker.new(check).call
    check
  end
end
