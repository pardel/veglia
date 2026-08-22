# Everything the dashboard needs about one vantage point, assembled
# once so the view does no querying of its own.
class NodeSummary
  WINDOWS = { "24 hours" => 24.hours, "7 days" => 7.days, "30 days" => 30.days }.freeze

  def initialize(node, now: Time.current)
    @node = node
    @now = now
  end

  attr_reader :node

  def latest = @latest ||= Check.for_node(node).order(:checked_at).last

  def status = latest&.status

  def known? = latest.present?

  # Stale means the app is not currently running, or is wedged. Saying
  # "up" because the last row happened to be green would be reporting
  # history as if it were the present.
  def stale?
    return true if latest.nil?
    now - latest.checked_at > Settings.gap_threshold_seconds
  end

  # How long the current status has held, found by walking back to the
  # first check that disagrees.
  def status_since
    return nil if latest.nil?

    boundary = Check.for_node(node)
                    .where.not(status: latest.status)
                    .where(checked_at: ..latest.checked_at)
                    .order(:checked_at)
                    .last

    boundary ? boundary.checked_at : Check.for_node(node).order(:checked_at).first&.checked_at
  end

  def machine_up_since = latest&.boot_at

  def stats = @stats ||= WINDOWS.transform_values { Stats.window(node: node, window: _1, now: now) }

  def heatmap = @heatmap ||= Heatmap.new(node: node, now: now)

  def outages
    @outages ||= Outage.for_node(node).recent.limit(15).to_a
  end

  def current_outage
    @current_outage ||= Outage.for_node(node).observed.open.order(:started_at).last
  end

  private

  attr_reader :now
end
