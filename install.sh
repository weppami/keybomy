#!/usr/bin/env bash
# Installs keybomy: links the plugin into the Omarchy shell and sets up the
# keybomyd system service. Run as yourself; it asks for sudo for the service.
#   ./install.sh            install, or update after changing the daemon
#   ./install.sh uninstall  remove the service and plugin link (keeps your data)
set -euo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="keybomy"
PLUGIN_LINK="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/keybomy"
UNIT="/etc/systemd/system/keybomyd.service"
# Root-owned copy: the daemon holds keyboard access, so your own processes must
# not be able to rewrite it (a copy in your home folder would let them).
DAEMON="/usr/local/lib/keybomy/keybomyd.py"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user; it uses sudo where needed." >&2
  exit 1
fi

if [[ ${1:-} == "uninstall" ]]; then
  sudo systemctl disable --now keybomyd.service 2>/dev/null || true
  sudo rm -f "$UNIT"
  sudo rm -rf "$(dirname "$DAEMON")"
  sudo systemctl daemon-reload
  [[ -L $PLUGIN_LINK ]] && rm "$PLUGIN_LINK"
  echo "Removed. Your stats are still in $DATA (delete that folder to erase them)."
  exit 0
fi


mkdir -p "$DATA"
chmod 700 "$DATA"

mkdir -p "$(dirname "$PLUGIN_LINK")"
if [[ -e $PLUGIN_LINK && ! -L $PLUGIN_LINK ]]; then
  echo "$PLUGIN_LINK exists and is not a link; leaving it alone." >&2
  exit 1
fi
ln -sfn "$SOURCE" "$PLUGIN_LINK"
echo "Plugin linked: $PLUGIN_LINK -> $SOURCE"

sudo install -Dm755 -o root -g root "$SOURCE/daemon/keybomyd.py" "$DAEMON"
sed -e "s|@SOURCE@|$SOURCE|g" -e "s|@DAEMON@|$DAEMON|g" -e "s|@DATA@|$DATA|g" \
    -e "s|@USER@|$USER|g" -e "s|@GROUP@|$(id -gn)|g" \
    "$SOURCE/daemon/keybomyd.service.in" | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable keybomyd.service
sudo systemctl restart keybomyd.service
echo "Service running: systemctl status keybomyd"

cat <<EOF

Next: add keybomy to your bar, e.g.
  omarchy bar put keybomy --section right
EOF
