#!/usr/bin/env sh
# Copy the in-app control panel into the relay's static surface (/panel).
# Run after editing YABAOCHEAT/Resources/panel, then restart the relay.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../YABAOCHEAT/Resources/panel"
dst="$here/public/menu"
mkdir -p "$dst"
cp "$src/index.html" "$src/panel.css" "$src/panel.js" "$src/panel-fonts.css" "$dst/"
cp "$src"/*.woff2 "$dst/"
echo "panel synced -> $dst"
