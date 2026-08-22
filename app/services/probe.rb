require "open3"
require "resolv"
require "net/http"
require "uri"

# One round of measurement, three tiers deep.
#
# The tiers exist so that a red light tells you *which* remedy applies.
# A single reachability boolean cannot distinguish a dead router from a
# dead ISP from a dead resolver, and those have nothing in common but
# the symptom.
#
# All three tiers, and the three HTTP endpoints within tier 3, run
# concurrently: a check costs about as long as its slowest probe rather
# than the sum of all of them, which matters when the answer has to
# land inside a one-minute cadence.
class Probe
  Result = Struct.new(
    :gateway_ok, :gateway_ms, :gateway_ip,
    :dns_ok, :dns_ms,
    :http_ok_count, :http_total, :http_ms,
    :detail,
    keyword_init: true
  )

  def self.call = new.call

  def call
    gateway = Thread.new { measure_gateway }
    dns     = Thread.new { measure_dns }
    http    = Thread.new { measure_http }

    gw = gateway.value
    dn = dns.value
    ht = http.value

    Result.new(
      gateway_ok: gw[:ok], gateway_ms: gw[:ms], gateway_ip: gw[:ip],
      dns_ok: dn[:ok], dns_ms: dn[:ms],
      http_ok_count: ht[:ok_count], http_total: ht[:total], http_ms: ht[:ms],
      detail: { gateway: gw, dns: dn, http: ht[:endpoints] }.to_json
    )
  end

  private

  # Tier 1 — the default gateway. If this fails, nothing beyond it is
  # diagnostic: the fault is inside the house.
  def measure_gateway
    ip = default_gateway_ip
    return { ok: false, ms: nil, ip: nil, error: "no default route" } if ip.blank?

    out, _err, status = Open3.capture3("/sbin/ping", "-c", "1", "-W", "1000", "-t", "2", ip)
    # Prefer the RTT ping itself reports over wall-clock, which would
    # include process spawn and make a healthy LAN look sluggish.
    rtt = out[/time=([\d.]+)\s*ms/, 1]&.to_f

    { ok: status.success?, ms: rtt, ip: ip }
  rescue Errno::ENOENT => e
    { ok: false, ms: nil, ip: nil, error: e.message }
  end

  def default_gateway_ip
    out, _err, status = Open3.capture3("/sbin/route", "-n", "get", "default")
    return nil unless status.success?
    out[/gateway:\s*(\S+)/, 1]
  rescue Errno::ENOENT
    nil
  end

  # Tier 2 — name resolution, timed on its own so a slow resolver is
  # visible before it becomes a failed resolver.
  def measure_dns
    started = monotonic
    Resolv::DNS.open do |resolver|
      resolver.timeouts = 2
      resolver.getaddress(Settings.dns_host)
    end
    { ok: true, ms: elapsed_ms(started) }
  rescue Resolv::ResolvError, Resolv::ResolvTimeout, IOError, SystemCallError => e
    { ok: false, ms: elapsed_ms(started), error: e.class.name }
  end

  # Tier 3 — actual reachability, across three independent operators.
  def measure_http
    endpoints = Settings.http_endpoints
    results = endpoints.map { |ep| Thread.new { fetch(ep) } }.map(&:value)

    successes = results.select { _1[:ok] }
    # Latency is the median of what worked. Averaging in a timeout
    # would report a number no request actually experienced.
    ms = median(successes.filter_map { _1[:ms] })

    { ok_count: successes.size, total: results.size, ms: ms, endpoints: results }
  end

  def fetch(endpoint)
    started = monotonic
    uri = URI.parse(endpoint[:url])
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 3) do |http|
      http.get(uri.request_uri)
    end
    { name: endpoint[:name], ok: response.code.to_i < 400, code: response.code.to_i, ms: elapsed_ms(started) }
  rescue StandardError => e
    { name: endpoint[:name], ok: false, code: nil, ms: nil, error: e.class.name }
  end

  def median(values)
    return nil if values.empty?
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0)
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def elapsed_ms(started) = ((monotonic - started) * 1000).round(1)
end
