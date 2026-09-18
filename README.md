# Open in Apple News

Paywalled links from Apple News+ publishers — WSJ, WIRED, The Atlantic, The New Yorker — open in the
News app instead of leaving you staring at a subscription wall in the browser.

Three separate pieces, because the three platforms have genuinely different constraints:

| Platform | Solution | Automatic? |
| --- | --- | --- |
| Safari on macOS | Safari web extension + native handler | Yes |
| Chrome on macOS | Chrome extension + native messaging host | Yes |
| iOS / iPadOS | Not possible — see [docs/ios.md](docs/ios.md) | No |

## How this actually works

The mechanism is the macOS **share service**, not a URL scheme. macOS ships
`/System/Applications/News.app/Contents/PlugIns/OpenInNews.appex`, a share extension that accepts a
web URL, and it is the only thing that resolves a publisher URL to its News+ article:

```swift
NSSharingService.sharingServices(forItems: [url])
    .first { $0.title == "Open in News" }?
    .perform(withItems: [url])
```

Things that were tried and **do not** work, so you don't repeat them:

- **`applenews://` / `applenewss://`** — these schemes are registered by News.app, and the widely
  repeated "swap `https` for `applenews`" bookmarklet does launch the app, but it lands on the
  **Today** screen. It does not resolve articles.
- **Shortcuts / App Intents** — News.app's only exposed intent is `ToggleAudioPlaybackIntent`. There
  is no "open article" intent to automate.

### Why the extension never closes your tab

The share service reports success even when it cannot find the article. Verified against
`example.com` and `news.ycombinator.com`: both return `DID_SHARE` and silently drop News to the
Today screen. There is no failure signal to act on.

So the extension is deliberately conservative — it hands the URL to News and leaves your browser tab
exactly where it is. A wrong guess costs you one ⌘-Tab back to the browser, never the page.

## Install

Two routes. Building from source is the better one — it signs with your own Apple Development
identity, which is what makes Safari keep the extension enabled — but there are
[pre-built downloads](#pre-built-downloads) if you would rather not install Xcode.

### Pre-built downloads

Every tagged release on the [Releases page](../../releases) carries a Chrome tarball, a Safari app
zip, and `checksums.txt`. They are built by GitHub Actions, which has no Apple identity, so they are
**ad-hoc signed and not notarized** — macOS treats them as unidentified software.

**Chrome.** Unpack with `tar` rather than double-clicking; Archive Utility quarantines what it
extracts, and Chrome refuses to launch a quarantined native host.

```sh
tar -xzf OpenInNews-chrome-<version>.tar.gz
cd OpenInNews-chrome-<version>
./install.sh          # installs and registers the native helper
```

Then load the `extension` folder at `chrome://extensions` with Developer mode on, and leave the
folder where it is — Chrome reloads it from that path every launch.

**Safari.**

```sh
unzip OpenInNews-safari-<version>.zip
xattr -dr com.apple.quarantine "Open in News.app"
mv "Open in News.app" /Applications/
```

Then follow the Safari steps below. One catch: an app without a Developer ID signature only keeps
its extension enabled while Safari's **Develop → Allow Unsigned Extensions** is ticked, and that
resets on every Safari restart. If that gets old, build from source instead — that is the whole
difference.

### Safari (macOS)

```sh
./scripts/stage.sh safari
open "safari/Open in News/Open in News.xcodeproj"   # build once, or use the script below
```

Or from the command line:

```sh
./scripts/build-safari.sh
```

Then:

1. Launch **Open in News.app** (it is installed to `/Applications`).
2. Click **Quit and Open Safari Extensions Preferences…**
3. Tick **Open in Apple News**.
4. Set its site access to **Allow on Every Website** — the extension needs to see navigations to
   know when you have landed on a publisher article.

### Chrome (macOS)

```sh
./scripts/build-chrome.sh
```

This compiles and signs the native messaging host into
`~/Library/Application Support/NewsOpen/`, and registers it with every Chromium-family browser it
finds (Chrome, Canary, Edge, Brave, Vivaldi, Arc).

Then, in `chrome://extensions`:

1. Turn on **Developer mode**.
2. **Load unpacked** → select `build/chrome/extension`.

The extension ID is pinned by the `key` field in the manifest, so it always matches the host
manifest's `allowed_origins`. Load it from that path and it just works.

### iOS / iPadOS

Not possible. iOS ships the same `OpenInNews.appex`, but its activation rule is `FALSEPREDICATE`,
so the share sheet can never offer it — verified against the iOS 27.0 simulator runtime. There is no
Shortcuts action and no URL scheme that resolves articles either. Full evidence in
[docs/ios.md](docs/ios.md).

## How it decides

1. **Allowlist.** `extension/publishers.js` seeds a conservative list of News+ publisher domains.
   Subdomains inherit from their parent domain.
2. **Article shape.** Section fronts, search, login, and account pages are skipped — a dated path
   (`/2026/09/18/…`), a long hyphenated slug, or a `/story/…` prefix counts as an article.
3. **Escape hatch.** If you navigate back to a URL it just redirected, it takes the hint and parks
   that URL for 15 minutes so you can read the web version in peace.
4. **It learns.** The toolbar button opens the current page in News on demand, and its *Always for
   this site* switch adds that publisher for next time.

Manage everything from the toolbar button → **Manage publishers…**

## Bonus: the command line

The Chrome host doubles as a standalone CLI, which is handy for Raycast, Alfred, or a macOS Shortcut
with a *Run Shell Script* action:

```sh
"$HOME/Library/Application Support/NewsOpen/newsopen-host" --open "https://www.wsj.com/…"
```

## Privacy

Nothing leaves your Mac. The extension talks only to a local native helper, which passes the URL to
Apple's own share service. There is no server, no analytics, and no network code in this project.

The extension requests broad host permissions because it has to see a navigation to decide whether
it is a publisher article — but it only ever acts on, and only ever sends, URLs matching your
allowlist.

## Layout

```
extension/        Shared web extension source (MV3) for both browsers
  publishers.js   Default News+ publisher allowlist
  background.js   Navigation matching, escape hatch, native hand-off
chrome/host/      Swift native messaging host + CLI
safari/           Generated Xcode project; the native handler lives in
                  "Open in News Extension/SafariWebExtensionHandler.swift"
scripts/          stage.sh, build-safari.sh, build-chrome.sh, install-host.sh,
                  package-release.sh, make_icons.py
docs/ios.md       Evidence for why iOS cannot be supported
```

`scripts/stage.sh <safari|chrome>` copies the shared source into `build/<target>/extension` with the
right manifest and native-helper ID baked in. Re-run it after editing anything in `extension/`.

## Releasing

```sh
./scripts/package-release.sh            # artifacts in build/release/
git tag v1.1 && git push origin v1.1    # Actions builds and publishes the same ones
```

`.github/workflows/release.yml` runs the same script on a tag push and attaches the artifacts to a
GitHub release; `workflow_dispatch` builds them without publishing, for a dry run. Run the script
locally instead and the artifacts pick up whatever signing identity your keychain has
(`CODESIGN_IDENTITY` for the host, `CODESIGN_TEAM` for the app), which the CI ones cannot — so a
locally built pair is worth uploading over them if you have a Developer ID.

## Known limitations

- **Resolution is Apple's, not ours.** A WSJ link resolved to the exact article in testing; one
  WIRED link opened a different WIRED story. What News does with a URL is entirely up to News.
- **No success signal**, as described above — hence the conservative allowlist.
- The publisher list is a hand-maintained seed. Apple publishes no machine-readable list of News+
  titles, so add what you read with the toolbar button.
- The `sharingServices(forItems:)` API is formally deprecated in favour of
  `NSSharingServicePicker`, which requires user interaction and therefore cannot be automated. The
  deprecated call is the only programmatic route, and it still works on macOS 27.
