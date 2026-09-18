#!/bin/zsh
# Build and register the Chrome native messaging host, and stage the extension.
#
#   ./scripts/build-chrome.sh
#
# Afterwards load build/chrome/extension as an unpacked extension at
# chrome://extensions (Developer mode on). The extension ID is pinned by the
# "key" field in the manifest, so the host manifest below always matches.
set -euo pipefail

ROOT="${0:A:h}/.."
HOST_NAME="com.yinka.newsopen"
EXT_ID="$(cat "$ROOT/chrome/extension_id.txt")"
INSTALL_DIR="$HOME/Library/Application Support/NewsOpen"
BIN="$INSTALL_DIR/newsopen-host"
IDENTITY="${CODESIGN_IDENTITY:-}"

"$ROOT/scripts/stage.sh" chrome

mkdir -p "$INSTALL_DIR"
echo "Building native host…"
xcrun swiftc -O "$ROOT/chrome/host/newsopen-host.swift" -o "$BIN"

if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')"
fi
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp=none "$BIN"
  echo "Signed host with: $IDENTITY"
else
  codesign --force --sign - "$BIN"
  echo "No Developer ID found; ad-hoc signed the host."
fi

# Register the host with every Chromium-family browser present.
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
echo "Done."
echo "  Extension ID : $EXT_ID"
echo "  Host binary  : $BIN"
echo "  Load unpacked: $ROOT/build/chrome/extension"
