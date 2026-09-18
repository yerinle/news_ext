#!/bin/zsh
# Install and register the Chrome native messaging host.
#
#   ./install-host.sh [path/to/newsopen-host]
#
# Used two ways, which is why it resolves everything by looking around itself:
#
#   * from scripts/build-chrome.sh, on a binary just compiled into place
#   * as install.sh inside a release tarball, next to a pre-built binary
#
# Registers the host with every Chromium-family browser it finds, so the
# extension can reach it over native messaging.
set -euo pipefail

HERE="${0:A:h}"
HOST_NAME="com.yinka.newsopen"
INSTALL_DIR="$HOME/Library/Application Support/NewsOpen"
BIN="$INSTALL_DIR/newsopen-host"
SRC="${1:-$HERE/newsopen-host}"

# The extension ID is pinned by the manifest's "key" field, and the host manifest
# has to name the same one. Beside this script in a release tarball; up a level
# in the repo.
for candidate in "$HERE/extension_id.txt" "$HERE/../chrome/extension_id.txt"; do
  [[ -f "$candidate" ]] || continue
  EXT_ID="$(tr -d '[:space:]' < "$candidate")"
  break
done
if [[ -z "${EXT_ID:-}" ]]; then
  echo "error: extension_id.txt not found next to $HERE" >&2
  exit 1
fi

if [[ ! -f "$SRC" ]]; then
  echo "error: host binary not found: $SRC" >&2
  exit 1
fi

if [[ "${SRC:A}" != "$BIN" ]]; then
  mkdir -p "$INSTALL_DIR"
  cp "$SRC" "$BIN"
  chmod +x "$BIN"
fi

# A binary that arrived in a download carries com.apple.quarantine, and Chrome
# refuses to launch a quarantined native host.
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true

# Keep a real signature if the binary already has one; ad-hoc sign it otherwise
# so macOS will run it at all.
if ! codesign -v "$BIN" >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none "$BIN"
  echo "Ad-hoc signed the host."
fi

for profile in \
  "$HOME/Library/Application Support/Google/Chrome" \
  "$HOME/Library/Application Support/Google/Chrome Canary" \
  "$HOME/Library/Application Support/Microsoft Edge" \
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
  "$HOME/Library/Application Support/Vivaldi" \
  "$HOME/Library/Application Support/Arc"
do
  [[ -d "$profile" ]] || continue
  dir="$profile/NativeMessagingHosts"
  mkdir -p "$dir"
  cat > "$dir/$HOST_NAME.json" <<JSON
{
  "name": "$HOST_NAME",
  "description": "Hands article URLs to the macOS Open in News share service",
  "path": "$BIN",
  "type": "stdio",
  "allowed_origins": [ "chrome-extension://$EXT_ID/" ]
}
JSON
  echo "Registered host in: ${profile:t}"
done

echo
echo "  Extension ID : $EXT_ID"
echo "  Host binary  : $BIN"
if [[ -d "$HERE/extension" ]]; then
  echo "  Load unpacked: $HERE/extension"
fi
