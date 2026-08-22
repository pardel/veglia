# Veglia — operations

Installing, running and troubleshooting. For why it works this way, see
[ARCHITECTURE.md](ARCHITECTURE.md).

## Locations

| What | Where |
|---|---|
| Installed application | `~/Applications/veglia` |
| Databases, secret, logs | `~/.local/share/veglia` |
| launchd job | `/Library/LaunchDaemons/dev.pardel.veglia.plist` |
| Staged plist (before `sudo`) | `~/.local/share/veglia/dev.pardel.veglia.plist` |
| Dashboard | `http://<hostname>.local:1440` |

The application is deliberately **not** run from the repo checkout. See
ARCHITECTURE.md → Deployment shape.

## Installing

From the repo:

```sh
./deploy/install.sh
```

This runs entirely as your ordinary user: it copies the app, generates a
per-machine secret, installs gems, builds assets, prepares the database
and stages a launchd plist. It then prints two steps for you to run,
because both change how the machine behaves.

### Step 1 — install and start the service

```sh
sudo cp ~/.local/share/veglia/dev.pardel.veglia.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/dev.pardel.veglia.plist
sudo chmod 644 /Library/LaunchDaemons/dev.pardel.veglia.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.pardel.veglia.plist
```

### Step 2 — stop the machine sleeping

```sh
sudo pmset -a sleep 0 disablesleep 1   # a sleeping Mac stops probing
sudo pmset -a autorestart 1            # come back after a power cut
```

**This step matters more than it looks.** A machine that sleeps stops
writing checks, and Veglia will correctly but uselessly report those
minutes as unobserved. Coverage will sag and you will have a record of
your own power settings rather than of your internet.

## Day-to-day

```sh
sudo launchctl kickstart -k system/dev.pardel.veglia   # restart
sudo launchctl bootout    system/dev.pardel.veglia     # stop
sudo launchctl print      system/dev.pardel.veglia     # status
tail -f ~/.local/share/veglia/log/veglia.err.log       # logs
curl -s localhost:1440/health                          # current state
```

`/health` returns the honest pair:

```json
{"node":"studio","status":"up",
 "last_24h":{"uptime_percent":100.0,"coverage_percent":98.4,
             "observed_minutes":1417,"missing_minutes":23,
             "unstarted_minutes":0}}
```

`missing_minutes` is a hole Veglia left in its own record and is worth
alerting on; `unstarted_minutes` is window that predates the node's
first check and is not. A high `uptime_percent` beside a low
`coverage_percent` means the figure describes very little, which is the
one reading this endpoint exists to make impossible to miss.

## Upgrading

Re-run the installer, then restart. The wrapper runs `db:prepare` on
every start, so migrations apply themselves.

```sh
./deploy/install.sh
sudo launchctl kickstart -k system/dev.pardel.veglia
```

The installer uses `rsync --delete` but excludes `storage/`, `log/` and
`tmp/`, and the databases live outside the app directory anyway, so
history survives a redeploy.

## Adding another Mac

Copy the repo to the machine and run the same installer. Each node keeps
its own database and its own dashboard, identified by hostname:

```sh
./deploy/install.sh
```

Set `VEGLIA_NODE` first if two machines would otherwise report the same
name. Nothing needs to be configured on the existing node, and no secret
is copied between machines.

**There is no combined view yet.** Each node serves its own dashboard on
its own host, so comparing two means opening both. Rolling them into one
needs a hub the satellites push to, which is phase 2: node identity is
already on every row, so it arrives without a migration.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `VEGLIA_NODE` | hostname | this vantage point's name |
| `VEGLIA_STORAGE` | `storage` | where the SQLite databases live |
| `PORT` | `1440` | HTTP port |
| `VEGLIA_APP_DIR` | `~/Applications/veglia` | install target |
| `VEGLIA_DATA_DIR` | `~/.local/share/veglia` | data and logs |

Probe endpoints, the quorum, the degraded threshold, the 90-second gap
tolerance and the 90-day retention live in `app/models/settings.rb`.
Changing them means a redeploy, which is intentional: they are decisions,
not knobs.

## Troubleshooting

### The dashboard will not load

- **Is the service up?** `sudo launchctl print system/dev.pardel.veglia`,
  then the error log.
- **Is something else on the port?** `lsof -nP -iTCP:1440 -sTCP:LISTEN`.
  Port 4000 was the original choice and turned out to be Jekyll's
  default, already serving another site on this machine.
- **Redirected to `https://`?** `config.force_ssl` and
  `config.assume_ssl` both default to true in Rails production and are
  explicitly disabled here. If they come back during an upgrade, every
  request redirects to an HTTPS URL nothing is listening on and the page
  simply never loads.

### It says `lan_down` constantly but the internet works

The router is probably declining to answer ICMP. Classification checks
the HTTP quorum before the gateway precisely to avoid this, so a
persistent `lan_down` with a satisfied quorum should be impossible —
if you see it, that ordering has regressed and
`test/models/check_test.rb` has the guarding test.

Confirm with `ping -c1 $(route -n get default | awk '/gateway/{print $2}')`.

### No checks are being written

Check the Solid Queue scheduler started. The log should show four
processes at boot: supervisor, dispatcher, worker and scheduler, with
`connectivity_check` in the recurring schedule. If Puma is up but no
rows appear, `SOLID_QUEUE_IN_PUMA` is probably unset — the wrapper sets
it, so this points at the service being started some other way.

> When testing by hand, note that killing Puma alone leaves Solid
> Queue's **forked children running**, and they will happily keep
> writing checks. Kill the whole tree or the gap you are trying to
> create will not exist.

### Coverage is low but the machine was on

Either the machine slept (see step 2 above), or Veglia was not running.
The dashboard distinguishes these: a hole spanning a change of boot time
is recorded as `machine_reboot`, and one without as `app_gap`. Sleep
looks like an `app_gap`, since the kernel does not re-boot on wake.

### Latency looks terrible on the first check after a restart

Expected in development, not in production. The first probe in a
freshly-booted process pays Ruby's autoloading inside the probe threads
and can report seconds rather than milliseconds. Production eager-loads
at boot, so the first real check is as fast as the rest — measured at
71 ms against 15 ms for DNS. If you see it in production, eager loading
has been turned off.

## Data

Four SQLite databases in `~/.local/share/veglia`: primary, cache, queue
and, for the roll-ups, the primary again. Backing up means copying
`production.sqlite3`; nothing else holds history.

Retention is 90 days of raw per-minute checks. Each completed day is
rolled into `daily_stats` **before** the prune runs, so the long record
survives. Both happen nightly at 3:10am.

At one row a minute, a year of raw checks is about 525,000 rows, which
SQLite does not notice.
