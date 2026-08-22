require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  test "a fresh install renders rather than erroring on no data" do
    get root_path

    assert_response :success
    assert_match "Waiting for the first check", response.body
  end

  test "the dashboard shows the current status" do
    Check.create!(node: "testnode", checked_at: Time.current, status: Check::UP,
                  boot_at: 2.days.ago, http_ms: 45.0)

    get root_path

    assert_response :success
    assert_match "testnode", response.body
    assert_match "Up", response.body
  end

  test "uptime is never shown without coverage beside it" do
    50.times { |i| Check.create!(node: "testnode", checked_at: i.minutes.ago, status: Check::UP, boot_at: 2.days.ago) }

    get root_path

    assert_response :success
    assert_match "coverage", response.body
  end

  test "a node whose last check is old is reported as stale, not up" do
    Check.create!(node: "testnode", checked_at: 3.hours.ago, status: Check::UP, boot_at: 2.days.ago)

    get root_path

    assert_response :success
    assert_match "No recent data", response.body
  end

  test "unobserved minutes are reported as a failure of their own kind" do
    now = Time.current
    Check.create!(node: "testnode", checked_at: now - 3.hours, status: Check::UP, boot_at: 2.days.ago)
    Check.create!(node: "testnode", checked_at: now, status: Check::UP, boot_at: 2.days.ago)

    get root_path

    assert_response :success
    assert_match "min not observed", response.body
    # The hatched violet, never a shade from the connection ramp.
    assert_match "bar-unobserved", response.body
  end

  test "an ongoing outage is called out" do
    Check.create!(node: "testnode", checked_at: Time.current, status: Check::INTERNET_DOWN, boot_at: 2.days.ago)
    Outage.create!(node: "testnode", kind: Outage::INTERNET_DOWN, started_at: 20.minutes.ago)

    get root_path

    assert_response :success
    assert_match "Ongoing", response.body
  end

  test "health returns machine-readable state" do
    Check.create!(node: Settings.node_name, checked_at: Time.current, status: Check::UP, boot_at: 2.days.ago)

    get health_path

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal Settings.node_name, body["node"]
    assert_equal "up", body["status"]
    assert body["last_24h"].key?("coverage_percent")
  end
end
