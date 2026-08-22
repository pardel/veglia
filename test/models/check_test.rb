require "test_helper"

class CheckTest < ActiveSupport::TestCase
  def result(gateway_ok: true, dns_ok: true, http_ok_count: 3, http_ms: 50.0)
    Probe::Result.new(
      gateway_ok: gateway_ok, gateway_ms: 2.0, gateway_ip: "192.168.0.1",
      dns_ok: dns_ok, dns_ms: 10.0,
      http_ok_count: http_ok_count, http_total: 3, http_ms: http_ms,
      detail: "{}"
    )
  end

  test "everything working is up" do
    assert_equal Check::UP, Check.classify(result)
  end

  test "a satisfied quorum with a failing resolver is degraded, not down" do
    # Something answered, so the link exists; the resolver being unwell
    # is a quality problem rather than an outage.
    assert_equal Check::DEGRADED, Check.classify(result(dns_ok: false))
  end

  test "a satisfied quorum that is slow is degraded" do
    assert_equal Check::DEGRADED, Check.classify(result(http_ms: Settings.degraded_http_ms + 1))
  end

  test "quorum is two of three, so one failing endpoint is still up" do
    assert_equal Check::UP, Check.classify(result(http_ok_count: 2))
  end

  test "a router that declines to answer ICMP is not a dead LAN" do
    # The regression this guards: classifying on the gateway first would
    # report lan_down forever on any network whose router ignores ping,
    # while the internet was demonstrably working.
    assert_equal Check::UP, Check.classify(result(gateway_ok: false, http_ok_count: 3))
  end

  test "nothing answering and no gateway is a local failure" do
    assert_equal Check::LAN_DOWN, Check.classify(result(gateway_ok: false, http_ok_count: 0))
  end

  test "nothing answering with a live gateway and dead resolver blames DNS" do
    assert_equal Check::DNS_DOWN, Check.classify(result(dns_ok: false, http_ok_count: 0))
  end

  test "nothing answering with gateway and resolver healthy blames the ISP" do
    assert_equal Check::INTERNET_DOWN, Check.classify(result(http_ok_count: 0))
  end
end
