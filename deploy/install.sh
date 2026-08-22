#!/bin/bash
# Install Veglia on this Mac.
#
# The application is copied *out* of wherever this repo happens to live
# and into a stable path on the internal disk. That is not tidiness: a
# checkout on an external or encrypted volume mounts at *login*, while a
# LaunchDaemon starts at *boot*. A job pointing into /Volumes would fail
# on every reboot, which is the exact moment the monitor most needs to
# be running.
#
# Everything up to the launchd step runs as the ordinary user. The two
# commands that change how the machine behaves are printed at the end
# for you to run, rather than run for you.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${VEGLIA_APP_DIR:-$HOME/Applications/veglia}"
DATA_DIR="${VEGLIA_DATA_DIR:-$HOME/.local/share/veglia}"
# 1440, the number of minutes in a day and so the number of checks
# Veglia records in one. Chosen mainly because it is free: 3000 is taken
# by any stray `rails server` and 4000 is Jekyll's default.
PORT="${VEGLIA_PORT:-1440}"
NODE="${VEGLIA_NODE:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
LABEL="dev.pardel.veglia"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"

echo "==> Veglia install"
echo "    source : $SOURCE_DIR"
echo "    app    : $APP_DIR"
echo "    data   : $DATA_DIR"
echo "    node   : $NODE"
echo "    port   : $PORT"
echo

# --- 1. Copy the application to a path that exists at boot ------------
echo "==> Copying application"
mkdir -p "$APP_DIR" "$DATA_DIR/log"
rsync -a --delete \
  --exclude ".git/" \
  --exclude "storage/" \
  --exclude "log/" \
  --exclude "tmp/" \
  --exclude "node_modules/" \
  "$SOURCE_DIR/" "$APP_DIR/"

# --- 2. A secret this machine keeps to itself -------------------------
# Generated per machine rather than copied, so a second machine needs no
# secret handed to it, and kept in a file only its owner can read
# because /Library/LaunchDaemons is world-readable.
SECRET_FILE="$DATA_DIR/secret_key_base"
if [ ! -f "$SECRET_FILE" ]; then
  echo "==> Generating secret_key_base"
  ( umask 077; head -c 64 /dev/urandom | xxd -p -c 128 > "$SECRET_FILE" )
fi
chmod 600 "$SECRET_FILE"

# --- 3. Dependencies, assets, database --------------------------------
RUBY_BIN="$(ruby -e 'puts RbConfig::CONFIG["bindir"]')"
export PATH="$RUBY_BIN:$PATH"

cd "$APP_DIR"
echo "==> Installing gems"
bundle install --quiet

echo "==> Building assets"
export RAILS_ENV=production
export VEGLIA_STORAGE="$DATA_DIR"
export SECRET_KEY_BASE="$(cat "$SECRET_FILE")"
bin/rails assets:precompile >/dev/null

echo "==> Preparing database"
bin/rails db:prepare

# --- 4. Render the launchd job ----------------------------------------
echo "==> Rendering launchd job"
STAGED_PLIST="$DATA_DIR/$LABEL.plist"
sed -e "s|__USER__|$USER|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__APP_DIR__|$APP_DIR|g" \
    -e "s|__DATA_DIR__|$DATA_DIR|g" \
    -e "s|__RUBY_BIN__|$RUBY_BIN|g" \
    -e "s|__PORT__|$PORT|g" \
    -e "s|__NODE__|$NODE|g" \
    "$SOURCE_DIR/deploy/veglia.plist.template" > "$STAGED_PLIST"

echo
echo "==> Application installed."
echo
echo "Two steps remain, and both change how this machine behaves, so"
echo "they are yours to run rather than mine:"
echo
echo "  1. Install and start the service:"
echo
echo "     sudo cp \"$STAGED_PLIST\" \"$PLIST_PATH\""
echo "     sudo chown root:wheel \"$PLIST_PATH\""
echo "     sudo chmod 644 \"$PLIST_PATH\""
echo "     sudo launchctl bootstrap system \"$PLIST_PATH\""
echo
echo "  2. Stop the machine sleeping, or Veglia stops watching and will"
echo "     honestly but uselessly report those minutes as unobserved:"
echo
echo "     sudo pmset -a sleep 0 disablesleep 1"
echo "     sudo pmset -a autorestart 1   # come back after a power cut"
echo
echo "Then open:  http://$NODE.local:$PORT"
echo
echo "To reload after an update:  sudo launchctl kickstart -k system/$LABEL"
echo "To stop:                    sudo launchctl bootout system/$LABEL"
echo "Logs:                       $DATA_DIR/log/veglia.{out,err}.log"
