#!/bin/zsh
# Build the downloadable artifacts for a GitHub release.
#
#   ./scripts/package-release.sh [version]
#
# Version defaults to the current git tag, then to the manifest version.
# Everything lands in build/release/:
#
#   OpenInNews-chrome-<version>.tar.gz   extension + universal host + installer
#   OpenInNews-safari-<version>.zip      "Open in News.app"
#   checksums.txt
#
# Signing follows the same rules as the build scripts: a real identity if the
# keychain has one (CODESIGN_IDENTITY / CODESIGN_TEAM override), ad-hoc
# otherwise. CI has no identity, so its artifacts are ad-hoc signed — which is
# why the install notes tell people to unpack with tar and clear quarantine.
#
# Pass --skip-safari to build only the Chrome artifact (no Xcode needed).
set -euo pipefail

ROOT="${0:A:h}/.."
OUT="$ROOT/build/release"
SKIP_SAFARI=0
VERSION=""

for arg in "$@"; do
  case "$arg" in
    --skip-safari) SKIP_SAFARI=1 ;;
    -*) echo "usage: package-release.sh [version] [--skip-safari]" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/extension/manifest.chrome.json'))['version'])")"
fi
VERSION="${VERSION#v}"

rm -rf "$OUT"
mkdir -p "$OUT"

# A Developer ID certificate is the only one Gatekeeper accepts on someone
# else's Mac; Apple Development is for this machine only. Fall back to it, then
# to ad-hoc, so the script still produces something without any certificate.
DEV_ID="${DEVELOPER_ID:-}"
if [[ -z "$DEV_ID" ]]; then
  DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -z "$DEV_ID" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')"
fi

# Signing is only half of it: since macOS 10.15 a downloaded app must also be
# notarized, or Gatekeeper still refuses it. Set NOTARY_PROFILE to a profile
# stored with `xcrun notarytool store-credentials` to run that step.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

notarize() {
  local target="$1"
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARY_PROFILE unset; skipping notarization of ${target:t}."
    return
  fi
  local zip="$OUT/${target:t}-notarize.zip"
  ditto -c -k --keepParent "$target" "$zip"
  echo "Notarizing ${target:t}…"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$zip"
  # A ticket can only be stapled to a bundle, disk image or installer. A loose
  # executable relies on Gatekeeper's online check instead.
  if [[ -d "$target" ]]; then
    xcrun stapler staple "$target"
  fi
}

# ---------------------------------------------------------------- chrome

"$ROOT/scripts/stage.sh" chrome

STAGE="$OUT/OpenInNews-chrome-$VERSION"
mkdir -p "$STAGE"
cp -R "$ROOT/build/chrome/extension" "$STAGE/extension"
cp "$ROOT/chrome/extension_id.txt" "$STAGE/extension_id.txt"
cp "$ROOT/scripts/install-host.sh" "$STAGE/install.sh"
chmod +x "$STAGE/install.sh"

# Universal, so one download covers Apple silicon and Intel. Sign after lipo —
# joining two signed slices invalidates both signatures.
echo "Building native host (universal)…"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos12.0" \
    "$ROOT/chrome/host/newsopen-host.swift" -o "$OUT/newsopen-host-$arch"
done
lipo -create "$OUT/newsopen-host-arm64" "$OUT/newsopen-host-x86_64" \
  -output "$STAGE/newsopen-host"
rm -f "$OUT/newsopen-host-arm64" "$OUT/newsopen-host-x86_64"

if [[ -n "$DEV_ID" ]]; then
  # Hardened runtime and a secure timestamp are both preconditions for
  # notarization, so a Developer ID signature has to carry them.
  codesign --force --sign "$DEV_ID" --options runtime --timestamp "$STAGE/newsopen-host"
  echo "Signed host with: $DEV_ID"
  notarize "$STAGE/newsopen-host"
elif [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp=none "$STAGE/newsopen-host"
  echo "Signed host with: $IDENTITY"
else
  codesign --force --sign - --timestamp=none "$STAGE/newsopen-host"
  echo "No identity found; ad-hoc signed the host."
fi

cat > "$STAGE/README.txt" <<TXT
Open in Apple News — Chrome extension for macOS $VERSION

1. Unpack with tar in Terminal, not by double-clicking:

     tar -xzf OpenInNews-chrome-$VERSION.tar.gz

   Double-clicking hands the files to Archive Utility, which marks them
   quarantined, and Chrome will not launch a quarantined native host.

2. Install and register the native helper:

     cd OpenInNews-chrome-$VERSION
     ./install.sh

   It copies newsopen-host to ~/Library/Application Support/NewsOpen/ and
   registers it with every Chromium-family browser it finds.

3. Load the extension at chrome://extensions:

     - turn on Developer mode
     - Load unpacked -> select the "extension" folder next to this file

   Keep the folder where it is; Chrome loads it from that path every launch.

The extension ID is pinned by the manifest, so it always matches the helper's
allowed_origins. Nothing here talks to the network — the helper only hands URLs
to the macOS "Open in News" share service.

Uninstall: remove the extension in Chrome, delete
~/Library/Application Support/NewsOpen/, and delete com.yinka.newsopen.json
from each browser's NativeMessagingHosts folder.
TXT

tar -czf "$OUT/OpenInNews-chrome-$VERSION.tar.gz" -C "$OUT" "OpenInNews-chrome-$VERSION"
rm -rf "$STAGE"
echo "Packaged: OpenInNews-chrome-$VERSION.tar.gz"

# ---------------------------------------------------------------- safari

if (( SKIP_SAFARI )); then
  echo "Skipping Safari app."
else
  "$ROOT/scripts/stage.sh" safari

  PRODUCTS="$OUT/safari-products"
  TEAM="${CODESIGN_TEAM:-}"
  # The team is the OU of the signing certificate's subject.
  if [[ -z "$TEAM" && -n "$DEV_ID" ]]; then
    TEAM="${${DEV_ID##*\(}%\)}"
  fi

  if [[ -n "$DEV_ID" ]]; then
    # Developer ID distribution needs an archive export, not a plain build:
    # `xcodebuild build` signs with the development certificate whatever else
    # is in the keychain, which Gatekeeper rejects on another Mac.
    echo "Archiving Safari app for Developer ID (team: $TEAM)…"
    ARCHIVE="$OUT/OpenInNews.xcarchive"
    xcodebuild -project "$ROOT/safari/Open in News/Open in News.xcodeproj" \
      -scheme "Open in News" -configuration Release \
      -archivePath "$ARCHIVE" \
      OBJROOT="$OUT/safari-intermediates" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
      archive 2>&1 | grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)'

    cat > "$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

    mkdir -p "$PRODUCTS/Release"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" \
      -exportPath "$PRODUCTS/Release" \
      -exportOptionsPlist "$OUT/export.plist" \
      -allowProvisioningUpdates 2>&1 | grep -E 'error:|EXPORT (SUCCEEDED|FAILED)'
    rm -rf "$ARCHIVE" "$OUT/export.plist"

    notarize "$PRODUCTS/Release/Open in News.app"
  else
  # Universal, like the host: one download for Apple silicon and Intel.
  echo "Building Safari app (team: ${TEAM:-none, ad-hoc})…"
  if [[ -n "$TEAM" ]]; then
    xcodebuild -project "$ROOT/safari/Open in News/Open in News.xcodeproj" \
      -target "Open in News" -configuration Release \
      SYMROOT="$PRODUCTS" OBJROOT="$OUT/safari-intermediates" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
      build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  else
    xcodebuild -project "$ROOT/safari/Open in News/Open in News.xcodeproj" \
      -target "Open in News" -configuration Release \
      SYMROOT="$PRODUCTS" OBJROOT="$OUT/safari-intermediates" \
      ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  fi

  fi

  APP="$PRODUCTS/Release/Open in News.app"

  # Without a team, xcodebuild leaves only the linker's ad-hoc signature on the
  # executables and nothing on the bundle. Seal the bundle so the app at least
  # launches once the user clears quarantine.
  if [[ -z "$TEAM" && -z "$DEV_ID" ]]; then
    codesign --force --deep --sign - "$APP"
    echo "Ad-hoc signed the app bundle."
  fi

  # ditto, not zip: it is the only archiver that keeps an .app's symlinks and
  # signature intact.
  ditto -c -k --keepParent "$APP" "$OUT/OpenInNews-safari-$VERSION.zip"

  # Xcode registers whatever it builds with LaunchServices, and Safari then
  # lists this copy as a second, identical extension alongside the installed
  # one. Drop it before the directory goes.
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "$LSREGISTER" -u "$APP" 2>/dev/null || true

  rm -rf "$PRODUCTS" "$OUT/safari-intermediates"
  echo "Packaged: OpenInNews-safari-$VERSION.zip"
fi

# ---------------------------------------------------------------- checksums

cd "$OUT"
shasum -a 256 *.tar.gz *.zip > checksums.txt 2>/dev/null || shasum -a 256 *.tar.gz > checksums.txt
echo
cat checksums.txt
