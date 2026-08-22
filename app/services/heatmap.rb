# The last 24 hours as a strip of buckets, worst-status-wins.
#
# Buckets rather than raw minutes because 1,440 cells is more DOM than
# information; five minutes is fine enough to see a short drop and
# coarse enough to read at a glance. A bucket with no checks in it is
# "missing", which is a distinct colour from "up" and never quietly
# rendered as one.
#
# Two kinds of empty, and they are not the same claim. "Missing" is a
# hole in a record that had already started: Veglia was installed and
# was supposed to be writing a row, and did not, which is a failure of
# the monitor. "Unstarted" is the stretch before this node's first
# check ever landed, where there is nothing to blame anyone for. Fusing
# them would make every fresh install open on a day of manufactured
# fault, which is the same dishonesty as the old grey, pointing the
# other way.
class Heatmap
  # Plain integer seconds, not a Duration: the bucket edge is computed
  # by integer division and used as a Hash key, and a Duration key would
  # never match the Integer one built on lookup.
  BUCKET_SECONDS = 5.minutes.to_i
  MISSING   = "missing".freeze
  UNSTARTED = "unstarted".freeze

  # Worst wins, so a single bad minute is never hidden by the four good
  # ones sharing its bucket.
  SEVERITY = {
    Check::UP            => 0,
    Check::DEGRADED      => 1,
    Check::DNS_DOWN      => 2,
    Check::INTERNET_DOWN => 3,
    Check::LAN_DOWN      => 4
  }.freeze

  Bucket = Struct.new(:starts_at, :status, :count, keyword_init: true)

  def initialize(node:, window: 24.hours, now: Time.current)
    @node = node
    @window = window
    @now = now
  end

  def buckets
    @buckets ||= begin
      # Anchor to a bucket boundary so cells do not shuffle on every reload.
      last_edge = Time.zone.at((now.to_i / BUCKET_SECONDS) * BUCKET_SECONDS)
      first_edge = last_edge - window + BUCKET_SECONDS

      grouped = checks_by_bucket(first_edge)

      (0...(window / BUCKET_SECONDS).to_i).map do |i|
        edge = first_edge + (i * BUCKET_SECONDS)
        found = grouped[edge.to_i]
        Bucket.new(
          starts_at: edge,
          status: found ? found[:status] : empty_status(edge),
          count: found ? found[:count] : 0
        )
      end
    end
  end

  private

  attr_reader :node, :window, :now

  # A bucket that ended before the first check ever landed predates the
  # record rather than punching a hole in it.
  def empty_status(edge)
    return UNSTARTED if first_checked_at.nil? || edge + BUCKET_SECONDS <= first_checked_at
    MISSING
  end

  # Memoised through `defined?` rather than `||=`, because the answer is
  # legitimately nil on a node that has never checked, and `||=` would
  # then re-run the query for all 288 buckets.
  def first_checked_at
    return @first_checked_at if defined?(@first_checked_at)
    @first_checked_at = Check.for_node(node).minimum(:checked_at)
  end

  def checks_by_bucket(first_edge)
    rows = Check.for_node(node)
                .where(checked_at: first_edge..now)
                .pluck(:checked_at, :status)

    rows.each_with_object({}) do |(checked_at, status), acc|
      edge = (checked_at.to_i / BUCKET_SECONDS) * BUCKET_SECONDS
      existing = acc[edge]

      if existing.nil?
        acc[edge] = { status: status, count: 1 }
      else
        existing[:count] += 1
        existing[:status] = status if SEVERITY.fetch(status, 0) > SEVERITY.fetch(existing[:status], 0)
      end
    end
  end
end
