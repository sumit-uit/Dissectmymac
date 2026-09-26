# Business model

## How DissectMac makes money (the benchmark)

- **Freemium, one-time purchase.** The free tier ("The Essentials") has the treemap, power search, large files and
  live stats. Pro ("The Power Suite") costs **$12.99 once**, excluding tax, with a 15-day money-back guarantee.
  Pro adds the uninstaller, leftover cleanup, storage map and premium themes.
- No subscription, no account, 100% local processing.
- Acquisition comes from SEO content (e.g. "DaisyDisk alternatives") and software directory listings (Capterra,
  GetApp, Uptodown, Softonic).
- A near-identical competitor, MacDissect, sells Pro for $10 lifetime. The category is crowded, with free options
  too (GrandPerspective, OmniDiskSweeper, AppCleaner, Pearcleaner).

## Our model

| | |
|---|---|
| Free | Everything that *shows* the problem: storage map, collector, large/old files, search, live + menu bar monitor, and **scanning** in every cleaner |
| Pro | Everything that *fixes* it: cleaning in Junk, Uninstaller, Leftovers, Duplicates, Developer Cleanup, Startup Items, plus themes |
| Price | $12.99 one-time (launch at $9.99). Later: a $24.99 family licence for 5 Macs. Paid major upgrades every ~2 years, at a discount for existing users |
| Refunds | 15 days, no questions asked |

The key conversion moment: a free user runs **Scan for Junk** or **Find Duplicates**, sees "14.2 GB reclaimable",
clicks **Clean**, and gets the upgrade sheet. The value is concrete, which is why this app can charge more than
DissectMac while keeping its core free.

## Zero-server stack

| Need | Solution | Cost |
|---|---|---|
| Checkout, VAT/sales tax, refunds | **Lemon Squeezy** or **Paddle** (merchant of record) | ~5% + 50¢ per sale |
| License keys | Ed25519-signed keys verified offline (`scripts/license_tool.py`). Issue from a provider webhook or a tiny serverless function, or paste them manually at low volume | $0 |
| Updates | Sparkle + appcast.xml on GitHub Releases/Pages | $0 |
| Website | Static site (GitHub Pages / Cloudflare Pages) | $0 |
| Code signing & notarization | Apple Developer Program | $99/yr |

A $12.99 sale nets about $11.80 after provider fees. Fixed costs are about $99/yr plus a domain, so break-even is
roughly 10 sales a year.

### Automating key delivery without running a server

- **Lemon Squeezy / Paddle:** a `order_created` webhook → a Cloudflare Worker (free tier) that runs the same signing
  as `license_tool.py` with the private key in a Worker secret → emails the key via the provider's email API.
- **Simplest:** Gumroad/Lemon Squeezy can each generate their own keys, but they use online validation. Keep our
  Ed25519 format if the app must stay fully offline.

## Launch checklist

1. Replace `LicenseVerifier.productionPublicKey` and `LicenseManager.purchaseURL`.
2. Set `DEVELOPMENT_TEAM` in `project.yml`, archive, notarize, build a `.dmg`.
3. Landing page with screenshots, a privacy promise, and a free download.
4. SEO posts: "DaisyDisk alternatives", "What is System Data on Mac", "How to uninstall apps completely on Mac",
   "Delete node_modules everywhere". List on MacUpdate, Softonic, Uptodown, AlternativeTo, Product Hunt and Setapp.
5. Add Sparkle before the first public release, so every user can receive future updates.

## Differentiators vs DissectMac

- A developer cleanup section (DerivedData, simulators, `node_modules`, package-manager caches). Developers are a
  high-intent audience that DissectMac ignores.
- A duplicate finder and junk cleaner in the same app. Normally that takes Gemini plus CleanMyMac.
- A DaisyDisk-style collector, so nothing is removed until you review it.
- A menu bar monitor.
- Startup items, with broken launch agents flagged.
