module DashboardHelper
  # One vocabulary of colour for the whole dashboard, in two families.
  #
  # Amber through rose is the **connection** failing, ordered by how
  # much of the path has gone. Violet, hatched, is a **different**
  # failure: Veglia was not watching, so nothing can be said about
  # those minutes at all.
  #
  # "Not observed" used to be pale grey, on the reasoning that the
  # absence of knowledge is neither good news nor bad. That reasoning
  # was wrong, and it undercut the point of the application: a monitor
  # that stops observing has failed at its only job, and a stretch
  # nobody watched is a fault to go and fix, not a blank to shrug at.
  # What it must never do is impersonate an outage on the link, which
  # is why it gets its own hue and its own texture rather than a
  # place in the red ramp.
  STATUS_STYLES = {
    Check::UP            => { bar: "bg-emerald-500",  chip: "bg-emerald-500 text-white",  label: "Up" },
    Check::DEGRADED      => { bar: "bg-amber-400",    chip: "bg-amber-400 text-amber-950", label: "Degraded" },
    Check::DNS_DOWN      => { bar: "bg-orange-500",   chip: "bg-orange-500 text-white",   label: "DNS down" },
    Check::INTERNET_DOWN => { bar: "bg-red-500",      chip: "bg-red-500 text-white",      label: "Internet down" },
    Check::LAN_DOWN      => { bar: "bg-rose-700",     chip: "bg-rose-700 text-white",     label: "Local network down" },
    Heatmap::MISSING     => { bar: "bar-unobserved",  chip: "bg-violet-600 text-white",   label: "Not observed" },
    Heatmap::UNSTARTED   => { bar: "bg-slate-200 dark:bg-slate-800", chip: "bg-slate-400 text-white", label: "Before first check" }
  }.freeze

  # The connection tiers, in the order a legend should read them.
  CONNECTION_STATUSES = [ Check::UP, Check::DEGRADED, Check::INTERNET_DOWN, Check::LAN_DOWN ].freeze

  # A stale node is "not observed" happening right now, so it wears the
  # same failure colour rather than the neutral grey it used to.
  STALE_STYLE = { bar: "bar-unobserved", chip: "bg-violet-600 text-white", label: "Not observing" }.freeze

  def connection_statuses = CONNECTION_STATUSES

  def status_style(status) = STATUS_STYLES.fetch(status, STALE_STYLE)

  def status_bar_class(status) = status_style(status)[:bar]

  def status_chip_class(status) = status_style(status)[:chip]

  def status_label(status) = status_style(status)[:label]

  # "6d 4h", "14m", "38s" — enough resolution to be useful, never more
  # than two units, because nobody reads the third.
  def humanize_duration(seconds)
    return "—" if seconds.nil?

    seconds = seconds.round
    return "#{seconds}s" if seconds < 60

    parts = []
    days, rest = seconds.divmod(86_400)
    hours, rest = rest.divmod(3_600)
    minutes, _ = rest.divmod(60)

    parts << "#{days}d" if days.positive?
    parts << "#{hours}h" if hours.positive?
    parts << "#{minutes}m" if minutes.positive? && days.zero?

    parts.first(2).join(" ").presence || "0m"
  end

  # Percentages are shown to two decimals because the difference
  # between 99.99% and 100% is the whole point of measuring.
  def percent(value)
    return "—" if value.nil?
    "#{value.round(2)}%"
  end

  def milliseconds(value)
    return "—" if value.nil?
    "#{value.round} ms"
  end

  def local_time(time)
    return "—" if time.nil?
    time.in_time_zone.strftime("%d %b, %H:%M")
  end
end
