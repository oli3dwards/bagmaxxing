#!/bin/bash
# Builds lidawake and starts its background check and menu bar icon. Safe to re-run.
# If the one-time admin permission is missing, macOS asks for your password once.
# It installs a copy, so this folder can be moved or deleted afterwards.
set -euo pipefail
cd "$(dirname "$0")"
DIR="$HOME/Library/Application Support/lidawake"
ROOT="$DIR/app"
AGENTS="$HOME/Library/LaunchAgents"
uid=$(id -u)

if ! xcode-select -p >/dev/null 2>&1; then
  echo "lidawake is built with Apple's command line tools, and they aren't installed yet."
  echo "Run this, wait for it to finish, then run ./install.sh again:"
  echo "  xcode-select --install"
  exit 1
fi

mkdir -p build "$DIR" "$AGENTS" "$HOME/.local/bin"
swiftc -O -o build/lidawake-thermal src/thermal.swift
swiftc -O -o build/lidawake-menubar src/menubar.swift
chmod +x bin/lidawake install-root.sh uninstall.sh
[ -f "$DIR/mode" ] || echo on > "$DIR/mode"

if ! sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  echo "Asking macOS for your password once, to allow the sleep switch..."
  osascript -e "do shell script \"'$PWD/install-root.sh' '$(id -un)'\" with administrator privileges \
    with prompt \"lidawake needs permission to keep your Mac awake with the lid closed.\""
fi

for label in io.github.oli3dwards.lidawake io.github.oli3dwards.lidawake-menubar; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done

rm -rf "$ROOT"
mkdir -p "$ROOT"
cp -R bin lib build uninstall.sh "$ROOT/"
ln -sf "$ROOT/bin/lidawake" "$HOME/.local/bin/lidawake"

for label in io.github.oli3dwards.lidawake io.github.oli3dwards.lidawake-menubar; do
  sed -e "s|__ROOT__|$ROOT|g" -e "s|__HOME__|$HOME|g" "launchd/$label.plist" > "$AGENTS/$label.plist"
  launchctl bootstrap "gui/$uid" "$AGENTS/$label.plist"
done

"$ROOT/bin/lidawake" tick
"$ROOT/bin/lidawake" status

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo
     echo "To use the lidawake command, add this line to ~/.zshrc and open a new terminal:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
