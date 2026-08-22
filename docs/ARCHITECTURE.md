# Veglia — architecture

Why the pieces are shaped the way they are. For running it, see
[OPERATIONS.md](OPERATIONS.md); for a short overview, the
[README](../README.md).

## The constraint everything follows from

**A monitor running on the machine it monitors cannot observe its own
downtime.**

When the machine reboots or Veglia crashes, no row is written. The naive
reading of an empty stretch is "nothing was wrong", which is how home
dashboards report a flawless day for a day the machine spent switched
off. Every other decision here is downstream of refusing that.

Two mechanisms follow:

1. **Every check stamps the kernel boot time** (`sysctl -n
   kern.boottime`), so a later check can tell what a hole means.
2. **Every check opens by measuring the hole before it** rather than
   just writing its own row, because once the row is written the
   absence is harder to see.

And one reporting rule: **uptime is never rendered without coverage
beside it.** Uptime answers "of the minutes we watched, how many were
connected". Coverage answers "how many of the window's minutes did we
watch at all". Blended, they produce the reassuring fiction the whole
application exists to avoid.

## Probing

Three tiers, run concurrently in threads, so a check costs about as long
as its slowest probe rather than the sum. A round is typically ~50 ms.

| Tier | Implementation | Isolates |
|---|---|---|
| Gateway | `/sbin/route -n get default`, then `/sbin/ping -c1 -W1000 -t2` | router, Wi-Fi, cabling |
| DNS | `Resolv::DNS` with a 2 s timeout | name resolution |
| HTTP | three 204 endpoints via `Net::HTTP`, 2 s open / 3 s read | the ISP and beyond |

Everything is Ruby standard library. An application whose entire product
is an honest record should have as few dependencies as possible that
could break quietly.

**The RTT comes from `ping`'s own reported time**, not wall-clock around
the call, because wall-clock includes process spawn and would make a
healthy LAN look sluggish.

**HTTP latency is the median of what succeeded**, not the mean of
everything. Averaging a timeout into the figure reports a number no
request actually experienced.

**The quorum is two of three.** One provider having a bad day is that
provider's outage, not yours. The endpoints are deliberately run by
three different organisations (Cloudflare, Google, Apple) over plain
HTTP, which keeps TLS handshake latency out of the measurement.

## Classification

`Check.classify` reads the three tiers and names the *proximate* cause.
Order matters more than it looks:

```
if HTTP quorum met:
    DNS failed        -> degraded
    HTTP slow (>2 s)  -> degraded
    otherwise         -> up
else:
    gateway failed    -> lan_down
    DNS failed        -> dns_down
    otherwise         -> internet_down
```

**Working internet is checked first, before the gateway.** Plenty of
routers decline to answer ICMP. Classifying on the gateway first would
report `lan_down` forever on exactly those networks while the internet
was demonstrably working, which would make Veglia useless in a way that
looks like a real finding. A named regression test guards this.

`degraded` counts as connected. The link existed, so calling it downtime
would overstate the problem; it is surfaced separately instead.

## Data model

### `checks` — one row per minute per node

Node identity, `checked_at`, `status`, the three tiers' results, and
`boot_at`. HTTP results are stored as `http_ok_count` / `http_total`
rather than a boolean so the quorum decision stays auditable after the
fact, and `detail` keeps the raw per-endpoint JSON.

`checked_at` is stamped at the **start** of the round, not the end, so
rows land on a steady one-minute cadence instead of drifting by however
long the probes took.

### `outages` — a run of failure compressed into one span

Two families:

- **Observed** (`lan_down`, `dns_down`, `internet_down`) — recorded by
  `OutageTracker` while Veglia was watching.
- **Inferred** (`app_gap`, `machine_reboot`) — recorded by
  `GapDetector` from a hole in the record. These are the ones a monitor
  on the monitored machine would otherwise lose entirely.

Inferred outages are created already closed. `OutageTracker` scopes to
`observed` precisely so it can never reopen or rewrite one.

A change of failure kind ends one outage and begins another: DNS
recovering into a full internet outage is two facts, and collapsing them
would lose which is current.

### `daily_stats` — completed days, frozen

Raw checks are pruned after 90 days. Without this table that prune would
destroy the history it summarises, so the roll-up runs **first** and the
prune only removes days already summarised. Only completed days are
stored; today is still accumulating, and freezing a partial day would
understate its own coverage.

## Gap detection

On each run, before writing anything:

```
elapsed = now - previous_check.checked_at
if elapsed <= 90 s: nothing happened
else if boot_at > previous.boot_at + 5 s: the machine rebooted
else:                                     the app was missing
```

The 90-second threshold tolerates one late run without crying gap while
still catching a genuinely missed minute on the next check. The
five-second slack on boot time absorbs the small wobble between reads.

**A reboot is recorded as two spans, not one.** The machine was off from
the last check until it booted; then Veglia may have taken a further
while to start. Recording `machine_reboot` and a following `app_gap`
separately is more useful than one undifferentiated blob, and it means
the machine is not blamed for the application's slow start.

If boot time is unavailable (not macOS), the fallback blames the app
rather than the machine, because that is the claim the evidence
supports.

**One hole is one row, and the database enforces it.** `CheckRunner`
reads the last stored check and then asks `GapDetector` about the gap
before it, with nothing between the read and the write. That is
correct at one check a minute and wrong the moment two overlap, which
is precisely what recovery looks like: while the app is down the
scheduler banks the minutes it missed, and when it returns the worker's
three threads take three of them at once. All three see the same stale
predecessor, all three infer the same hole, all three write it down.
The live database had **41 rows describing 20 spans** before this was
caught, in groups of two and three created within milliseconds of each
other, and the dashboard listed the same interruption three times.

The fix is a unique index on `(node, kind, started_at)` with
`GapDetector#record` rescuing `RecordNotUnique` and returning the row
that won. Widening the read-write window instead — a lock, a
transaction, a longer look-back — would have made the race rarer while
leaving it possible, and this is a monitor: a duplicated outage is a
lie about how often the thing failed.

## Statistics

`Stats` takes an explicit range, so the dashboard's rolling windows and
the nightly per-day roll-up share one implementation instead of two that
can disagree.

```
expected_minutes  = range length in minutes      (what the clock says)
observed_minutes  = rows actually written        (what we saw)
unstarted_minutes = range before the first check (no record yet)
missing_minutes   = expected - observed - unstarted   (a hole we left)

uptime   = (up + degraded) / observed
coverage = observed / expected
```

The two kinds of unobserved minute are split for the same reason the
heatmap splits them: `missing` is a fault to go and fix, `unstarted`
predates the record and is nobody's. A 30-day window on a day-old node
is almost entirely `unstarted`, and colouring that as failure would be
the old grey's dishonesty told the other way round. Coverage is
computed against `expected` regardless, because "we watched 4% of the
last 30 days" stays true however good the reason.

`uptime_percent` returns **nil** when nothing was observed, rather than
0% or 100%. An unknown figure must not render as either.

## Heatmap

288 buckets of five minutes over 24 hours. Buckets rather than 1,440 raw
minutes because that is more DOM than information; five minutes is fine
enough to see a short drop and coarse enough to read at a glance.

**Worst status wins within a bucket**, so a single bad minute is never
hidden by the four good ones sharing it. A bucket with no checks is
`missing`, which is a distinct colour from `up` and never quietly
rendered as one.

**`missing` is a failure, and not a connection failure.** It first
shipped as pale grey, on the reasoning that the absence of knowledge is
neither good news nor bad. That was wrong, and it worked against the
point of the application: a monitor that stops observing has failed at
its only job, and a stretch nobody watched is a fault to go and fix
rather than a blank to shrug at. The dashboard therefore reads in two
colour families, and the whole design rests on not confusing them:

| Family | Colours | Claim |
|---|---|---|
| Connection | amber → orange → red → rose | the link broke, ordered by how much of the path went |
| Coverage | hatched violet | Veglia was not watching, so no claim about the link is available |

The hatch does work a flat fill cannot: it says there is no measurement
underneath the colour, rather than a bad one. Uptime and coverage stay
two numbers exactly as before — nothing about `missing` is folded into
`down_minutes` or into `uptime_percent`, because a failure of the
monitor is not evidence of a failure of the link.

**`unstarted` is the third state, and it is not a failure.** Buckets
that end before this node's first check ever landed predate the record
rather than punching a hole in it, and they stay neutral grey. Without
the distinction every fresh install would open on a day of manufactured
fault, which is the same dishonesty as the old grey pointing the other
way.

Buckets are anchored to a fixed boundary so cells do not shuffle on
every reload.

> Implementation note: `BUCKET_SECONDS` must stay a plain integer. It was
> once `5.minutes`, an `ActiveSupport::Duration`, used as a Hash key
> built by integer division — the key never matched on lookup and every
> bucket came back empty, which would have shipped a permanently blank
> heatmap.

## Scheduling and process model

Solid Queue recurring tasks in `config/recurring.yml` (`schedule: every
minute`), with `plugin :solid_queue` in `puma.rb` so the supervisor runs
**inside Puma**. The whole application is one process under one launchd
job, rather than a web process and a worker that can drift out of step.

`CheckJob` swallows its own exceptions and logs them: a failed check
must never take the scheduler down, because the next minute's run is the
recovery, and the absence of that row is recorded anyway.

## Multiple nodes

Each node is **self-sufficient** — its own SQLite, its own probes, its
own dashboard, no dependency on any peer being alive.

This is worth doing for a reason beyond redundancy: one vantage point
cannot distinguish "the internet is down" from "this machine's network
stack is wedged". Two can, and two disagreeing is itself the finding.

**Phase 2** designates one node as hub; satellites push their rows to it
while retaining local history, so a hub outage costs freshness and
nothing else. Node identity is on every row from the first migration, so
that arrives without a schema change.

The hub's ingest endpoint accepts writes from other machines, which is a
different security posture from today's read-only LAN app. It wants a
host allow-list and a shared secret introduced at the same time.

## Deployment shape

**launchd, not Docker.** Kamal would mean Docker on each Mac and a
registry round-trip to deploy to a machine in the same room.

**A `LaunchDaemon`, not a `LaunchAgent`.** An agent starts at login, and
a headless machine that reboots at 4am may sit for days with nobody logged
in. The daemon starts at boot and drops to the named user via
`UserName`, so nothing runs as root beyond launchd itself.

**Installed outside the repo.** If the checkout lives on an external or
encrypted volume, that volume mounts at *login* while the daemon starts
at *boot*; a job pointing into `/Volumes` would fail on every reboot,
which is precisely when the monitor most needs to be running. The
installer copies to `~/Applications/veglia` with data in
`~/.local/share/veglia`.

**`SECRET_KEY_BASE` lives in a 0600 file**, generated per machine, not
in the plist — `/Library/LaunchDaemons` is world-readable. This also
means `config/master.key` is not a deployment dependency, so a second
Mac needs no secret handed to it.

## Deliberate omissions

- **No alerting.** Adding it means deciding what to do at 3am, and that
  is a separate decision.
- **No exposure beyond the LAN.** No tunnel, no port forwarding.
- **No authentication**, which is defensible only while the app is
  read-only on a home network. It stops being defensible when the hub's
  ingest endpoint arrives.
- **No host authorisation allow-list.** Veglia answers to several
  legitimate names (`.local`, bare hostname, a DHCP-assigned IP), and an
  over-tight list fails as a dashboard that will not load with nothing
  on screen to explain why.
