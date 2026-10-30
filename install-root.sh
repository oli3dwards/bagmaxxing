#!/bin/bash
# One-time admin step: lets USER flip macOS's hidden sleep switch without a password.
# It allows exactly two commands, nothing else:
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
#
# Run as root, e.g. from install.sh via the macOS admin password dialog:
#   sudo ./install-root.sh "$(id -un)"
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

user=${1:?usage: install-root.sh USERNAME}
id "$user" >/dev/null
[ "$(id -u)" = 0 ] || { echo "must run as root" >&2; exit 1; }

rule=/etc/sudoers.d/lidawake
tmp=$(mktemp)
cat > "$tmp" <<EOF
# lidawake: keep the Mac running with the lid closed.
$user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF
visudo -cf "$tmp" >/dev/null
install -m 0440 -o root -g wheel "$tmp" "$rule"
rm -f "$tmp"
echo "installed $rule"
