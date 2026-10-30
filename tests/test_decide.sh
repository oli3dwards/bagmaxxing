#!/bin/bash
# Tests for lib/decide.sh. Run: bash tests/test_decide.sh
set -u
cd "$(dirname "$0")/.."
. lib/decide.sh

LOW_BATTERY=15 RESUME_BATTERY=20 HOT_SECONDS=180
NOW=1000000
fails=0

check() { # description expected mode power pct thermal hot_since cut
  local name=$1 want=$2; shift 2
  local got; got=$(decide "$@" "$NOW")
  if [ "$got" = "$want" ]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

#     name                                   want(WANT REASON HOT_SINCE CUT)  mode power   pct thermal  hot_since cut
check "on, mains, cool: stay awake"          "1 on - -"                        on   ac      100 nominal  -         -
check "on, battery 80%: stay awake"          "1 on - -"                        on   battery 80  fair     -         -
check "switched off: normal sleep"           "0 off - -"                       off  ac      100 nominal  -         -
check "off clears a cut-out"                 "0 off - -"                       off  battery 10  nominal  -         battery
check "battery at threshold: cut"            "0 battery - battery"             on   battery 15  nominal  -         -
check "battery below threshold: cut"         "0 battery - battery"             on   battery 9   nominal  -         -
check "battery 16%: still awake"             "1 on - -"                        on   battery 16  nominal  -         -
check "cut sticks until resume level"        "0 battery - battery"             on   battery 19  nominal  -         battery
check "cut lifts at resume level"            "1 on - -"                        on   battery 20  nominal  -         battery
check "cut lifts on mains power"             "1 on - -"                        on   ac      10  nominal  -         battery
check "unknown battery never cuts"           "1 on - -"                        on   unknown ""  nominal  -         -
check "heat starts the clock"                "1 on $NOW -"                     on   ac      100 serious  -         -
check "heat under 3 min: stay awake"         "1 on $((NOW-179)) -"             on   ac      100 serious  $((NOW-179)) -
check "heat for 3 min: cut"                  "0 heat $((NOW-180)) heat"        on   ac      100 critical $((NOW-180)) -
check "cooling clears the heat cut"          "1 on - -"                        on   ac      100 fair     $((NOW-900)) heat
check "unknown thermal never cuts"           "1 on - -"                        on   ac      100 unknown  -         -
check "battery wins over heat"               "0 battery $((NOW-600)) battery"  on   battery 5   serious  $((NOW-600)) -

check_sleep() { # description expected(yes|no) cut lid switch idle
  local name=$1 want=$2 got=no; shift 2
  should_sleep "$@" && got=yes
  if [ "$got" = "$want" ]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n     want: %s\n     got:  %s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

#           name                                 want cut     lid    switch idle
check_sleep "cut-out, lid shut, nobody there"    yes  battery closed 0      300
check_sleep "heat counts too"                    yes  heat    closed 0      300
check_sleep "2 minutes idle is enough"           yes  battery closed 0      120
check_sleep "used 1 minute 59 ago: wait"         no   battery closed 0      119
check_sleep "no cut-out: stay awake"             no   -       closed 0      300
check_sleep "lid open: never"                    no   battery open   0      300
check_sleep "lid unknown: never"                 no   battery unknown 0     300
check_sleep "switch stuck on: sleeping can't work" no battery closed 1      300
check_sleep "idle unreadable: assume nobody"     yes  battery closed 0      ""

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
