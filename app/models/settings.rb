require "socket"

# Every tunable in one place. Veglia has no admin UI on purpose: the
# things worth changing are changed in the launchd plist or here, and
# both are under version control.
module Settings
  # The node's identity. Defaults to the hostname so a second machine
  # needs no configuration at all, but can be overridden when two
  # machines would otherwise report the same name.
  def self.node_name
    ENV.fetch("VEGLIA_NODE") { Socket.gethostname.sub(/\.local\z/, "") }
  end

  # A check is expected every minute. Ninety seconds allows one late
  # run without crying gap, while still catching a genuinely missed
  # minute on the next check.
  def self.gap_threshold_seconds = 90

  # Raw per-minute checks are kept this long; daily roll-ups outlive them.
  def self.retention_days = 90

  # Independent captive-portal endpoints, chosen because they return a
  # tiny 204 and are run by three different organisations. Plain HTTP
  # keeps TLS handshake latency out of the measurement.
  def self.http_endpoints
    [
      { name: "cloudflare", url: "http://cp.cloudflare.com/generate_204" },
      { name: "google",     url: "http://connectivitycheck.gstatic.com/generate_204" },
      { name: "apple",      url: "http://captive.apple.com/hotspot-detect.html" }
    ]
  end

  # Two of three must answer. One provider having a bad day is that
  # provider's outage, not yours.
  def self.http_quorum = 2

  def self.dns_host = "cloudflare.com"

  # Above this, the connection is up but not well.
  def self.degraded_http_ms = 2000
end
