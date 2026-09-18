#!/bin/zsh
# Build and install the Safari extension app.
#
#   ./scripts/build-safari.sh
#
# Signs with the first "Apple Development" identity in your keychain, which is
# what lets Safari keep the extension enabled across restarts. Override with
# CODESIGN_TEAM=<team id>.
set -euo pipefail

ROOT="${0:A:h}/.."
PROJECT="$ROOT/safari/Open in News/Open in News.xcodeproj"
PRODUCTS="$ROOT/build/safari/products"

"$ROOT/scripts/stage.sh" safari

# Resolve the team ID from the signing identity that actually has a private key.
# The keychain usually holds several expired "Apple Development" certificates,
# and matching by name alone picks the wrong one.
TEAM="${CODESIGN_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  TEAM="$(python3 - <<'PY'
import re, subprocess

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout

usable = set(re.findall(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"Apple Development',
                        run('security find-identity -v -p codesigning'), re.M))

blob = run('security find-certificate -a -c "Apple Development" -Z -p')
for block in blob.split('SHA-1 hash: ')[1:]:
    sha1 = block.split('\n', 1)[0].strip()
    if sha1 not in usable:
        continue
    pem = block[block.find('-----BEGIN CERTIFICATE-----'):]
    pem = pem[:pem.find('-----END CERTIFICATE-----') + len('-----END CERTIFICATE-----')]
    subject = subprocess.run('openssl x509 -noout -subject', shell=True,
                             input=pem, capture_output=True, text=True).stdout
    found = re.search(r'OU\s*=\s*([A-Z0-9]+)', subject)
    if found:
        print(found.group(1))
        break
PY
)"
fi

echo "Building (team: ${TEAM:-none, ad-hoc})…"
if [[ -n "$TEAM" ]]; then
  xcodebuild -project "$PROJECT" -target "Open in News" -configuration Release \
    SYMROOT="$PRODUCTS" OBJROOT="$ROOT/build/safari/intermediates" \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
    build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
else
  xcodebuild -project "$PROJECT" -target "Open in News" -configuration Release \
    SYMROOT="$PRODUCTS" OBJROOT="$ROOT/build/safari/intermediates" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
fi

APP="$PRODUCTS/Release/Open in News.app"
DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Open in News.app"
cp -R "$APP" "$DEST/"

# Xcode registers whatever it builds with LaunchServices, so the copy under
# build/ would show up in Safari as a second, identical extension. Drop it and
# leave only the installed one.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -f "$DEST/Open in News.app" 2>/dev/null || true

echo
echo "Installed: $DEST/Open in News.app"
echo "Next: launch it, open Safari Settings > Extensions, tick \"Open in Apple News\","
echo "      and set site access to \"Allow on Every Website\"."
