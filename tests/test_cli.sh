#!/bin/bash
# End-to-end tests: runs the real bin/bagmaxxing, install.sh and uninstall.sh in a throwaway
# HOME. macOS's own commands are replaced by shell functions, so nothing here can touch
# the Mac's real sleep setting. Run: bash tests/test_cli.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export FAKE="$SANDBOX/fake"
FAKE_HOME="$SANDBOX/home"
DIR="$FAKE_HOME/Library/Application Support/bagmaxxing"
AGENTS="$FAKE_HOME/Library/LaunchAgents"
CLONE="$SANDBOX/clone"
LABEL=io.github.oli3dwards.bagmaxxing
fails=0

# The fake Mac. Each command reads the world from files in $FAKE and records what it did.
pmset() {
  case "$*" in
    "-g batt") printf "Now drawing from '%s'\n -InternalBattery-0 (id=20316259)\t%s%%; discharging; 3:00 remaining present: true\n" \
                 "$(cat "$FAKE/power")" "$(cat "$FAKE/pct")" ;;
    "-g") printf ' SleepDisabled\t\t%s\n' "$(cat "$FAKE/switch")" ;;
    sleepnow) echo sleepnow >> "$FAKE/calls" ;;
  esac
}
sudo() {
  [ -e "$FAKE/sudo_ok" ] || return 1
  [ "$2" = -l ] && return 0
  echo "$5" > "$FAKE/switch"
  echo "switch $5" >> "$FAKE/calls"
}
ioreg() {
  case "$*" in
    *AppleClamshellState*) printf '      "AppleClamshellState" = %s\n' "$(cat "$FAKE/lid")" ;;
    *IOHIDSystem*) printf '    | |   "HIDIdleTime" = %s000000000\n' "$(cat "$FAKE/idle")" ;;
  esac
}
curl() { echo "curl $*" >> "$FAKE/calls"; [ ! -e "$FAKE/curl_fails" ]; }
route() { printf '  interface: en0\n'; }
launchctl() { echo "launchctl $1" >> "$FAKE/calls"; }
swiftc() { touch "$3"; chmod +x "$3"; }
osascript() { [ -e "$FAKE/refuse_admin" ] && return 1; touch "$FAKE/sudo_ok"; }
export -f pmset sudo ioreg curl route launchctl swiftc osascript

# A hyphen can't be exported as a function, and install.sh keeps the caller's PATH.
mkdir -p "$SANDBOX/stubs"
printf '#!/bin/bash\n[ ! -e "$FAKE/no_tools" ]\n' > "$SANDBOX/stubs/xcode-select"
chmod +x "$SANDBOX/stubs/xcode-select"
export PATH="$SANDBOX/stubs:$PATH"

for c in pmset sudo ioreg curl route launchctl swiftc osascript; do
  [ "$(/bin/bash -c "type -t $c")" = function ] || { echo "$c is not stubbed; refusing to run"; exit 1; }
done

world() { # power pct lid idle thermal switch
  case $1 in ac) echo "AC Power" ;; *) echo "Battery Power" ;; esac > "$FAKE/power"
  echo "$2" > "$FAKE/pct"; echo "$3" > "$FAKE/lid"; echo "$4" > "$FAKE/idle"
  echo "$5" > "$FAKE/thermal"; echo "$6" > "$FAKE/switch"
}

fresh() { # bagmaxxing installed, with phone alerts on and nothing recorded yet
  rm -rf "$FAKE" "$FAKE_HOME"
  mkdir -p "$FAKE" "$DIR/app/build" "$AGENTS" "$FAKE_HOME/.local/bin"
  cp -R "$REPO/bin" "$REPO/lib" "$REPO/uninstall.sh" "$DIR/app/"
  printf '#!/bin/bash\ncat "$FAKE/thermal"\n' > "$DIR/app/build/bagmaxxing-thermal"
  chmod +x "$DIR/app/build/bagmaxxing-thermal"
  touch "$FAKE/calls" "$FAKE/sudo_ok"
  echo 'NTFY_TOPIC=test-topic' > "$DIR/config.sh"
}

cli() { HOME="$FAKE_HOME" /bin/bash "$DIR/app/bin/bagmaxxing" "$@"; }
count() { grep -c -- "$1" "$FAKE/calls"; }
contains() { case $1 in *"$2"*) echo yes ;; *) echo no ;; esac; }

is() { # name got want
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$1" "$3" "$2"
    fails=$((fails + 1))
  fi
}

# --- the background check

fresh; world battery 14 Yes 300 nominal 1; cli tick
is "low battery, lid shut: lets go of the switch"  "$(cat "$FAKE/switch")" 0
is "low battery, lid shut: sends one alert"        "$(count 'curl ')" 1
is "low battery, lid shut: sleeps"                 "$(count sleepnow)" 1
is "the alert says why"                            "$(contains "$(cat "$FAKE/calls")" 'Battery is at 14%')" yes
is "the alert goes to the configured topic"        "$(contains "$(cat "$FAKE/calls")" 'https://ntfy.sh/test-topic')" yes

fresh; world battery 14 Yes 30 nominal 1; cli tick
is "someone at the keyboard: no sleep yet"         "$(count sleepnow)" 0
is "someone at the keyboard: no alert yet"         "$(count 'curl ')" 0
echo 300 > "$FAKE/idle"; cli tick
is "they walk away: it still sleeps"               "$(count sleepnow)" 1
is "they walk away: it still alerts"               "$(count 'curl ')" 1

fresh; world battery 14 Yes 300 nominal 1; cli tick; cli tick; cli tick
is "a cut-out that lasts: sleeps every time"       "$(count sleepnow)" 3
is "a cut-out that lasts: alerts once"             "$(count 'curl ')" 1

fresh; world battery 14 Yes 300 nominal 1; cli tick
world ac 14 Yes 300 nominal 0; cli tick
world battery 14 Yes 300 nominal 1; cli tick
is "a second cut-out alerts again"                 "$(count 'curl ')" 2

fresh; echo 'HOT_SECONDS=0' >> "$DIR/config.sh"; world ac 100 Yes 300 serious 1; cli tick
is "hot, lid shut: sleeps"                         "$(count sleepnow)" 1
is "hot, lid shut: the alert says why"             "$(contains "$(cat "$FAKE/calls")" 'running hot')" yes

fresh; world battery 14 No 300 nominal 1; cli tick
is "lid open: lets go of the switch"               "$(cat "$FAKE/switch")" 0
is "lid open: never sleeps the Mac"                "$(count sleepnow)" 0

fresh; world ac 100 No 300 nominal 0; cli tick
is "healthy: turns the switch on"                  "$(cat "$FAKE/switch")" 1

fresh; echo '- -' > "$DIR/state"; world battery 14 Yes 300 nominal 1; cli tick
is "reads a state file from an older version"      "$(count sleepnow)" 1

fresh; rm "$DIR/config.sh"; world battery 14 Yes 300 nominal 1; cli tick
is "no phone set up: still sleeps"                 "$(count sleepnow)" 1
is "no phone set up: sends nothing"                "$(count 'curl ')" 0

fresh; touch "$FAKE/curl_fails"; world battery 14 Yes 300 nominal 1; cli tick
is "no signal: still sleeps"                       "$(count sleepnow)" 1
is "no signal: says so in the log"                 "$(contains "$(cli log)" 'FAILED to send')" yes

fresh; rm "$FAKE/sudo_ok"; world battery 14 Yes 300 nominal 1; cli tick
is "no permission: reported to the menu bar"       "$(contains "$(cat "$DIR/status")" 'error=no-permission')" yes
is "no permission: status says so"                 "$(contains "$(cli status)" 'NOT WORKING')" yes

# --- uninstall

fresh; world ac 100 No 300 nominal 1; touch "$AGENTS/$LABEL.plist" "$AGENTS/$LABEL-menubar.plist"
ln -s "$DIR/app/bin/bagmaxxing" "$FAKE_HOME/.local/bin/bagmaxxing"
out=$(cli uninstall)
is "uninstall stops the check before the switch"   "$(tail -n 1 "$FAKE/calls")" "switch 0"
is "uninstall stops both background jobs"          "$(count 'launchctl bootout')" 2
is "uninstall turns the switch off"                "$(cat "$FAKE/switch")" 0
is "uninstall says the switch is back to normal"   "$(contains "$out" 'back to normal')" yes
is "uninstall removes the background jobs"         "$(ls "$AGENTS" | wc -l | tr -d ' ')" 0
is "uninstall removes the command"                 "$([ -e "$FAKE_HOME/.local/bin/bagmaxxing" ] && echo there || echo gone)" gone
is "uninstall removes the installed copy"          "$([ -e "$DIR/app" ] && echo there || echo gone)" gone

fresh; world ac 100 No 300 nominal 1; rm "$FAKE/sudo_ok"
out=$(cli uninstall)
is "uninstall warns if the switch is stuck on"     "$(contains "$out" 'sudo pmset -a disablesleep 0')" yes
is "uninstall doesn't claim success if it's stuck" "$(contains "$out" 'back to normal')" no

# --- install

new_clone() {
  rm -rf "$CLONE" "$FAKE" "$FAKE_HOME"
  mkdir -p "$CLONE" "$FAKE"
  touch "$FAKE/calls"
  cp -R "$REPO/bin" "$REPO/lib" "$REPO/launchd" "$REPO/src" "$REPO/install.sh" \
        "$REPO/install-root.sh" "$REPO/uninstall.sh" "$CLONE/"
  world ac 100 No 300 nominal 0
}
do_install() { HOME="$FAKE_HOME" /bin/bash "$CLONE/install.sh" 2>&1; }

new_clone; out=$(do_install)
is "install asks for the permission and carries on" "$(count 'launchctl bootstrap')" 2
is "install fills in the background job paths"     "$(grep -c '__' "$AGENTS/$LABEL.plist" "$AGENTS/$LABEL-menubar.plist" | cut -d: -f2 | tr -d '\n')" 00
is "install writes valid background jobs"          "$(plutil -lint -s "$AGENTS/$LABEL.plist" "$AGENTS/$LABEL-menubar.plist" && echo valid)" valid
is "install points the job at the installed copy"  "$(grep -c 'Application Support/bagmaxxing/app/bin/bagmaxxing' "$AGENTS/$LABEL.plist")" 1
is "install says how to fix PATH"                  "$(contains "$out" 'export PATH')" yes
is "install ends by showing the status"            "$(contains "$out" 'Lid-closed mode: ON')" yes
is "install turns the switch on itself"            "$(cat "$FAKE/switch")" 1
rm -rf "$CLONE"
is "it survives the clone being deleted"           "$(contains "$(HOME="$FAKE_HOME" /bin/bash "$FAKE_HOME/.local/bin/bagmaxxing" status)" 'Lid-closed mode:')" yes

new_clone; touch "$FAKE/no_tools"; out=$(do_install); code=$?
is "no Apple tools: stops"                         "$code" 1
is "no Apple tools: says what to run"              "$(contains "$out" 'xcode-select --install')" yes
is "no Apple tools: installs nothing"              "$([ -e "$DIR/app" ] && echo there || echo clean)" clean

new_clone; touch "$FAKE/refuse_admin"; out=$(do_install); code=$?
is "permission refused: stops"                     "$([ "$code" -ne 0 ] && echo stopped || echo carried-on)" stopped
is "permission refused: installs nothing"          "$([ -e "$DIR/app" ] && echo there || echo clean)" clean
is "permission refused: starts no background job"  "$(count 'launchctl bootstrap')" 0

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
