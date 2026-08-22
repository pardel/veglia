class Outage < ApplicationRecord
  # Observed directly, while Veglia was watching.
  LAN_DOWN       = "lan_down".freeze
  DNS_DOWN       = "dns_down".freeze
  INTERNET_DOWN  = "internet_down".freeze

  # Inferred from a hole in the record. These are the ones a monitor
  # running on the machine it monitors would otherwise lose entirely.
  APP_GAP        = "app_gap".freeze
  MACHINE_REBOOT = "machine_reboot".freeze

  OBSERVED = [ LAN_DOWN, DNS_DOWN, INTERNET_DOWN ].freeze
  INFERRED = [ APP_GAP, MACHINE_REBOOT ].freeze

  scope :for_node,  ->(node) { where(node: node) }
  scope :open,      -> { where(ended_at: nil) }
  scope :observed,  -> { where(kind: OBSERVED) }
  scope :inferred,  -> { where(kind: INFERRED) }
  scope :recent,    -> { order(started_at: :desc) }

  def ongoing? = ended_at.nil?

  def duration
    duration_s || (Time.current - started_at).round
  end

  def label
    case kind
    when LAN_DOWN       then "Local network"
    when DNS_DOWN       then "DNS"
    when INTERNET_DOWN  then "Internet"
    when APP_GAP        then "Veglia not running"
    when MACHINE_REBOOT then "Machine rebooted"
    else kind.humanize
    end
  end
end
