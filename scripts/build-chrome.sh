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
fi

# Registers the host with every Chromium-family browser present, and ad-hoc
# signs it if the step above found no identity.
"$ROOT/scripts/install-host.sh" "$BIN"

echo "  Load unpacked: $ROOT/build/chrome/extension"
