# iOS and iPadOS

**There is no working solution on iOS, and none can be built with supported APIs.** This document
records what was checked, so the question doesn't get reopened on a hunch.

## What was verified

Inspected directly from the iOS 27.0 simulator runtime shipped with Xcode 27
(`/Library/Developer/CoreSimulator/Volumes/iOS_24A5423a/…/RuntimeRoot/Applications/News.app`).

### The share extension exists, but is switched off

iOS News.app contains `PlugIns/OpenInNews.appex`, the same extension name as macOS. Its `Info.plist`:

```
NSExtensionPointIdentifier  = com.apple.services
NSExtensionActivationRule   = FALSEPREDICATE
FRExtensionActivationRule   = FUNCTION(FUNCTION(CAST('MCProfileConnection','Class'),
                              'sharedConnection'),'effectiveParametersForBoolSetting:','allowNews').value == 1
```

`FALSEPREDICATE` never matches, so the extension can never be offered through the normal share-sheet
activation path. It is reachable only through News's own private `FRExtensionActivationRule`, and
that rule is an MDM/configuration-profile check on `allowNews` — not a user-facing setting.

For contrast, the macOS build of the same extension declares:

```
NSExtensionPointIdentifier = com.apple.share-services
NSExtensionActivationRule  = { NSExtensionActivationSupportsWebURLWithMaxCount = 1 }
```

which is exactly why *Share → Open in News* exists on the Mac and not on the phone.

### There is no alternative hook

| Hook | iOS 27 status |
| --- | --- |
| Share sheet action | Gated off with `FALSEPREDICATE` (above) |
| URL schemes | `applenews:` / `applenewss:` registered, same as macOS — they launch News on **Today** and do not resolve articles |
| Shortcuts / App Intents | One action only: `ToggleAudioPlaybackIntent`. No "open article" action |
| Direct resolution | `OpenInNews` is a thin shim over News's internal XPC, trafficking in `articleID`, not URLs. No callable endpoint |
| Safari web extension | Could detect a publisher article, but has nothing to hand the URL to |

`applenews:///<articleID>` and `https://apple.news/<id>` *do* open a specific article — but deriving
that ID from a publisher URL requires the private resolution path that only the gated extension can
reach.

### The automatic redirect

Older coverage (iOS 14 era) describes a *Open Web Links in News* toggle under Settings → News that
redirected News+ publisher links into the app. That behaviour was reported as gone by iOS 15, and it
does not occur on iOS 27 in practice. Do not rely on second-hand articles about it; they are stale.

## What to do instead

Nothing automated. In practice:

- Read those articles on the Mac, where this project's extension handles it.
- On the phone, open News and find the story there directly — News's own search is the only route
  from a headline to the News+ copy.

## If you want to re-check this in a future iOS release

```sh
xcrun simctl list runtimes           # runtimes live under /Library/Developer/CoreSimulator/Volumes
R="/Library/Developer/CoreSimulator/Volumes/<iOS_BUILD>/Library/Developer/CoreSimulator/Profiles/Runtimes/<iOS X.Y>.simruntime/Contents/Resources/RuntimeRoot/Applications/News.app"
plutil -p "$R/PlugIns/OpenInNews.appex/Info.plist"
```

If `NSExtensionActivationRule` ever becomes `NSExtensionActivationSupportsWebURLWithMaxCount`, the
share sheet option is back and iOS becomes solvable.
