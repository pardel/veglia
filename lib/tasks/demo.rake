# Fill the development database with a day covering every state the
# dashboard can report.
#
#   bin/rails demo:seed
#
# Why this exists. A healthy connection produces a dashboard with one colour
# on it, which says nothing about what the thing does when the connection is
# not healthy. The alternative is a hand-made screenshot, and a picture of
# failures that never happened is the same lie the whole application is built
# to avoid. This way the picture is reproducible: anyone can run the task and
# get it.
#
# It refuses to run in production. The point of Veglia is that its record is
# what actually happened, and seeding invented rows into the real database
# would destroy exactly that.
namespace :demo do
  DAY = 24 * 60

  desc "One node, every status and every outage kind"
  task seed: :environment do
    abort "demo:seed refuses to run in production: the record has to be what happened." if Rails.env.production?

    node = ENV.fetch("NODE", "demo-mini")
    days = Integer(ENV.fetch("DAYS", "8"))
    now = Time.current.change(sec: 0)
    boot = now - (days * DAY + 400).minutes

    Check.delete_all
    Outage.delete_all
    DailyStat.delete_all

    # Windows of non-`up` minutes, as [from_minutes_ago, to_minutes_ago, status].
    windows = [
      [ 1_050, 1_032, Check::INTERNET_DOWN ],
      [   870,   862, Check::DNS_DOWN ],
      [   610,   601, Check::LAN_DOWN ],
      [   455,   436, Check::DEGRADED ],
      [   120,   116, Check::DEGRADED ]
    ]

    # Holes in the record. Nothing is written for these minutes: that absence
    # is the evidence, and it is what the inferred outages are read from.
    reboot_gap = [ 760, 718 ]
    app_gap    = [ 300, 262 ]
    in_gap = ->(ago) { [ reboot_gap, app_gap ].any? { |from, to| ago <= from && ago >= to } }

    connected = ->(status) { [ Check::UP, Check::DEGRADED ].include?(status) }

    rows = []
    (0...(days * DAY)).each do |ago|
      next if in_gap.call(ago)

      at = now - ago.minutes
      window = windows.find { |from, to, _| ago <= from && ago >= to }
      status = window ? window[2] : Check::UP

      rows << {
        node: node, checked_at: at, status: status,
        # The boot time moves once, at the reboot, which is what lets that
        # gap be read as the machine's downtime rather than as Veglia's.
        boot_at: ago > reboot_gap[1] ? boot : now - (reboot_gap[1] - 1).minutes,
        gateway_ok: status != Check::LAN_DOWN,
        gateway_ms: status == Check::LAN_DOWN ? nil : rand(0.6..3.0).round(2),
        dns_ok: connected.call(status),
        dns_ms: connected.call(status) ? rand(4.0..40.0).round(1) : nil,
        http_ok_count: connected.call(status) ? 3 : 0,
        http_total: 3,
        http_ms: (rand(900.0..1_800.0).round(1) if status == Check::DEGRADED) ||
                 (rand(28.0..70.0).round(1) if status == Check::UP),
        detail: status == Check::DEGRADED ? "http quorum met, slow" : nil,
        created_at: at, updated_at: at
      }
    end
    Check.insert_all!(rows)

    outages = [
      { kind: Outage::INTERNET_DOWN, from: 1_050, to: 1_032,
        detail: "http quorum 0/3; dns unresolved; gateway answered" },
      { kind: Outage::DNS_DOWN, from: 870, to: 862,
        detail: "resolver silent; gateway and http both fine" },
      { kind: Outage::LAN_DOWN, from: 610, to: 601,
        detail: "gateway unreachable; nothing above it answered" },
      { kind: Outage::MACHINE_REBOOT, from: reboot_gap[0], to: reboot_gap[1],
        detail: "kern.boottime moved; the downtime is the machine's" },
      { kind: Outage::APP_GAP, from: app_gap[0], to: app_gap[1],
        detail: "machine was up; Veglia had not started" }
    ].map do |o|
      started = now - o[:from].minutes
      ended = now - o[:to].minutes
      { node: node, kind: o[:kind], started_at: started, ended_at: ended,
        duration_s: (ended - started).to_i, detail: o[:detail],
        created_at: ended, updated_at: ended }
    end
    Outage.insert_all!(outages)

    stats = (1..29).map do |back|
      missing = back.in?([ 3, 11, 18 ]) ? rand(40..140) : rand(0..6)
      down = back.in?([ 5, 12 ]) ? rand(8..30) : 0
      degraded = rand(0..25)
      observed = DAY - missing
      { node: node, day: now.to_date - back, expected_minutes: DAY,
        observed_minutes: observed, up_minutes: observed - down - degraded,
        down_minutes: down, degraded_minutes: degraded,
        p50_ms: rand(30.0..60.0).round(1), p95_ms: rand(90.0..600.0).round(1),
        created_at: now, updated_at: now }
    end
    DailyStat.insert_all!(stats)

    puts "Seeded #{node}: #{rows.size} checks, #{outages.size} outages, #{stats.size} days."
    puts "Every check status: up, degraded, dns_down, internet_down, lan_down."
    puts "Every outage kind: observed (lan, dns, internet) and inferred (app gap, reboot)."
    puts "Run bin/dev and open http://localhost:3000"
  end
end
