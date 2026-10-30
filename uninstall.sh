#!/bin/bash
# Removes lidawake and puts lid-close sleep back to normal.
set -uo pipefail
uid=$(id -u)
DIR="$HOME/Library/Application Support/lidawake"

# The background check goes first, or its next tick could turn the switch back on.
for label in io.github.oli3dwards.lidawake io.github.oli3dwards.lidawake-menubar; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done

sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null
if [ "$(pmset -g 2>/dev/null | awk '$1 == "SleepDisabled" { print $2 }')" = 1 ]; then
  echo "WARNING: the sleep switch is still on, so this Mac won't sleep with the lid closed."
  echo "Turn it off with:  sudo pmset -a disablesleep 0"
else
  echo "sleep switch back to normal"
fi

rm -f "$HOME/.local/bin/lidawake"
rm -rf "$DIR/app"
echo "removed. To drop the admin permission too:  sudo rm /etc/sudoers.d/lidawake"
echo "Your settings and log are still in: $DIR"
