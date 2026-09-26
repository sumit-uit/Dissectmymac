# DissectMyMac

A native macOS disk analyzer and cleaner that works 100% offline. It combines the best of DissectMac, DaisyDisk,
CleanMyMac, AppCleaner/Pearcleaner, Gemini, DevCleaner and Stats/iStat Menus in one app. There is no server, no
account and no telemetry.

## Features

| | Feature | Inspired by | Free | Pro |
|---|---|---|:-:|:-:|
| **Analyze** | Storage map: two-level squarified treemap, drill-down, breadcrumbs, size-by-type breakdown | DissectMac, DaisyDisk, GrandPerspective | ✅ | ✅ |
| | Collector: stage files from anywhere (right-click / drag), review, then move to Trash | DaisyDisk | ✅ | ✅ |
| | Large & old files: biggest files, and big files untouched for a year | OmniDiskSweeper | ✅ | ✅ |
| | Power search: wildcards, kind/type/size filters | DissectMac | ✅ | ✅ |
| | Live monitor: CPU, memory, disk, network, battery, thermal state, history chart | Stats, iStat Menus | ✅ | ✅ |
| | Menu bar monitor | Stats | ✅ | ✅ |
| **Clean** | Junk cleaner: caches, logs, crash reports, iOS updates, Xcode, package managers, browsers, Trash, installers | CleanMyMac, DevCleaner | scan | ✅ |
| | App uninstaller: app + containers, caches, prefs, launch agents; drag an app onto the window | AppCleaner, Pearcleaner | scan | ✅ |
| | Leftover cleanup: orphaned files from apps deleted long ago | DissectMac, Pearcleaner | scan | ✅ |
| | Duplicate finder: size → partial hash → full SHA-256 | Gemini, dupeGuru | scan | ✅ |
| | Developer cleanup: `node_modules`, `Pods`, `target`, `.build`, `venv`, `.next`, … | npkill, DevCleaner | scan | ✅ |
| | Startup items: launch agents and daemons, broken items flagged | CleanMyMac, KnockKnock | view | ✅ |
| | Premium themes: Forest, Ocean, Aurora | DissectMac | | ✅ |

Free users can **scan** everything and see how much they could reclaim. Pro unlocks the **clean** action. The upgrade
prompt appears at the moment the value is clearest.

### Safety

- Every removal goes through `Trash.moveToTrash`, which moves items to the Trash so they can be recovered, never deletes them outright.
- `SafetyPolicy` refuses to touch system roots, `/System`, `/usr`, your home folder and top-level Library folders.
- Only categories that apps rebuild automatically are pre-selected in the junk cleaner. Backups, archives and installers are opt-in.
- Orphan detection never lists `com.apple.*` items, or anything owned by an installed app or one of its helpers.

## Project layout

```
Sources/DissectCore/        UI-free engine (unit-tested)
  Scanning/                 DiskScanner (cancellable, stays on one volume), FileSize
  Treemap/                  Squarified treemap layout
  Finders/                  Large/old files, power search, category breakdown, DuplicateFinder
  Apps/                     AppCatalog, LeftoverMatcher/LeftoverScanner
  Cleaning/                 JunkCleaner, DevProjectScanner, Trash + SafetyPolicy
  System/                   SystemMonitor (CPU/mem/battery/disk/network), StartupItems
  Licensing/                Offline Ed25519 license verification, ProFeature
Sources/DissectMyMac/       SwiftUI app (sidebar sections, menu bar extra, settings, upgrade flow)
Tests/DissectCoreTests/     XCTest suite
scripts/license_tool.py     Key pair generation + license issuing
project.yml                 XcodeGen spec for the signed/notarized .app
```

## Build & run

Requires macOS 14+ and Xcode 16+.

```sh
swift test                    # run the engine tests
swift run DissectMyMac        # quick run during development
DMM_UNLOCK_PRO=1 swift run DissectMyMac   # debug builds only: unlock Pro without a key

# Real .app bundle (for signing & notarization)
brew install xcodegen
xcodegen generate && open DissectMyMac.xcodeproj
```

On first launch, grant **Full Disk Access** (System Settings → Privacy & Security). Without it, macOS hides Mail,
Safari, Messages and other protected folders from any app. The app shows a banner with a shortcut to the setting.

## Licensing (no server)

1. `pip install cryptography && python3 scripts/license_tool.py keygen`
2. Put the **public** key in `LicenseVerifier.productionPublicKey`. Keep the **private** key secret, for example in a password manager or a CI secret.
3. Issue keys per sale with `license_tool.py issue --email …`, or automatically from your payment provider (see `docs/BUSINESS.md`).
4. The app verifies the signature offline. Nothing is ever sent anywhere.

## Distribution

The app **must not be sandboxed**: reading the whole disk and removing other apps' files is impossible inside the App
Sandbox. That rules out the Mac App Store. Distribute directly instead:

1. Archive in Xcode, sign with a **Developer ID Application** certificate (Apple Developer Program, $99/yr).
2. Notarize: `xcrun notarytool submit DissectMyMac.zip --keychain-profile … --wait`, then `xcrun stapler staple`.
3. Ship a `.dmg` from your website. For auto-updates, add [Sparkle](https://sparkle-project.org) with an appcast hosted on GitHub Releases/Pages.

See [`docs/BUSINESS.md`](docs/BUSINESS.md) for the revenue model and launch plan.
