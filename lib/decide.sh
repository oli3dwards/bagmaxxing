# bagmaxxing's decision rule, kept free of side effects so it can be tested.
# Sourced by bin/bagmaxxing and tests/test_decide.sh.
#
# decide MODE POWER PCT THERMAL HOT_SINCE CUT NOW
#   MODE       on | off            (the menu bar switch)
#   POWER      ac | battery | unknown
#   PCT        battery percentage, empty if unknown
#   THERMAL    nominal | fair | serious | critical | unknown  (macOS's own reading)
#   HOT_SINCE  epoch seconds when heat strain began, or -
#   CUT        cut-out in force after the last tick: battery | heat | -
#   NOW        epoch seconds
# Needs LOW_BATTERY, RESUME_BATTERY and HOT_SECONDS set.
#
# Prints "WANT REASON HOT_SINCE CUT":
#   WANT    1 = keep running with the lid closed, 0 = let the Mac sleep normally
#   REASON  on | off | battery | heat

decide() {
  local mode=$1 power=$2 pct=$3 thermal=$4 hot_since=$5 cut=$6 now=$7
  [ "$hot_since" = - ] && hot_since=
  [ "$cut" = - ] && cut=

  # Heat clock: runs while macOS reports serious or critical strain, resets as soon as it cools.
  case $thermal in
    serious|critical) [ -n "$hot_since" ] || hot_since=$now ;;
    *) hot_since= ;;
  esac

  # A battery cut-out holds until mains power or RESUME_BATTERY, so it can't flap around the threshold.
  local battery_cut=0
  if [ "$power" = battery ] && [ -n "$pct" ]; then
    if [ "$pct" -le "$LOW_BATTERY" ]; then
      battery_cut=1
    elif [ "$cut" = battery ] && [ "$pct" -lt "$RESUME_BATTERY" ]; then
      battery_cut=1
    fi
  fi

  local heat_cut=0
  if [ -n "$hot_since" ] && [ $((now - hot_since)) -ge "$HOT_SECONDS" ]; then
    heat_cut=1
  fi

  local hs=${hot_since:--}
  if [ "$mode" = off ]; then
    echo "0 off $hs -"
  elif [ "$battery_cut" = 1 ]; then
    echo "0 battery $hs battery"
  elif [ "$heat_cut" = 1 ]; then
    echo "0 heat $hs heat"
  else
    echo "1 on $hs -"
  fi
}

# should_sleep CUT LID SWITCH IDLE
#   CUT     cut-out in force: battery | heat | -
#   LID     closed | open | unknown
#   SWITCH  the hidden switch as it stands now: 1 | 0
#   IDLE    seconds since the last keyboard or mouse input, empty if unknown
# True when a cut-out is in force, the lid is shut and nobody is using the Mac. Input in the
# last 2 minutes may mean it's docked to an external screen, so it waits. It can't work with
# the switch still on, because the switch is what stops the Mac sleeping.

should_sleep() {
  local cut=$1 lid=$2 switch=$3 idle=${4:-}
  [ "$cut" != - ] && [ "$lid" = closed ] && [ "$switch" = 0 ] && [ "${idle:-999}" -ge 120 ]
}
