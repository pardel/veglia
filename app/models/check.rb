class Check < ApplicationRecord
  UP            = "up".freeze
  DEGRADED      = "degraded".freeze
  DNS_DOWN      = "dns_down".freeze
  INTERNET_DOWN = "internet_down".freeze
  LAN_DOWN      = "lan_down".freeze

  # Degraded counts as connected. The link existed, so calling it
  # downtime would overstate the problem; it is surfaced on its own
  # rather than folded into either bucket.
  HEALTHY  = [ UP, DEGRADED ].freeze
  OUTAGES  = [ LAN_DOWN, DNS_DOWN, INTERNET_DOWN ].freeze

  scope :for_node, ->(node) { where(node: node) }
  scope :since,    ->(time) { where(checked_at: time..) }
  scope :healthy,  -> { where(status: HEALTHY) }
  scope :down,     -> { where(status: OUTAGES) }

  # Reads the three tiers and names the proximate cause.
  #
  # Order matters. Working internet is checked *first*, because plenty
  # of routers decline to answer ICMP: a failed gateway ping alongside
  # a satisfied HTTP quorum means a quiet router, not a dead LAN, and
  # classifying it as lan_down would make Veglia useless on exactly
  # those networks.
  def self.classify(result)
    quorum_met = result.http_ok_count.to_i >= Settings.http_quorum

    if quorum_met
      return DEGRADED unless result.dns_ok
      return DEGRADED if result.http_ms && result.http_ms > Settings.degraded_http_ms
      return UP
    end

    # Nothing answered. Now the lower tiers say where it broke.
    return LAN_DOWN unless result.gateway_ok
    return DNS_DOWN unless result.dns_ok
    INTERNET_DOWN
  end

  def healthy? = HEALTHY.include?(status)
  def down?    = OUTAGES.include?(status)

  def self.nodes = distinct.order(:node).pluck(:node)
end
