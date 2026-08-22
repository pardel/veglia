class DashboardController < ApplicationController
  def index
    @generated_at = Time.current
    @summaries = node_names.map { NodeSummary.new(_1, now: @generated_at) }
  end

  # Plain JSON, so the state is legible to something other than a
  # browser without anyone having to scrape the dashboard.
  def health
    summary = NodeSummary.new(Settings.node_name)
    day = summary.stats["24 hours"]

    render json: {
      node: summary.node,
      status: summary.stale? ? "stale" : summary.status,
      checked_at: summary.latest&.checked_at,
      machine_up_since: summary.machine_up_since,
      last_24h: {
        uptime_percent: day.uptime_percent&.round(2),
        coverage_percent: day.coverage_percent&.round(2),
        observed_minutes: day.observed_minutes,
        # Split, because they are different claims: one is a hole Veglia
        # left in its own record, the other predates the record.
        missing_minutes: day.missing_minutes,
        unstarted_minutes: day.unstarted_minutes
      }
    }
  end

  private

  # Before the first check lands there is nothing in the table, and a
  # blank page would read as breakage rather than as a fresh install.
  def node_names
    Check.nodes.presence || [ Settings.node_name ]
  end
end
