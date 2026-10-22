# Changelog

Versions are `MAJOR.MINOR.PATCH`.

> **Tags never move.** Once a tag points at a commit, that is where it points
> forever. Anything that needs fixing gets the next number.

---

## v1.0.6

**English documentation, and the build no longer embeds Swift source paths.**

- `README.md` is now **English**; the Korean text moved to `README.ko.md` and the
  two link to each other. The README states the supported scope, lists the
  ClassDB API, and says plainly that the plugin makes no network calls.
- `CHANGELOG.md` is English too, and the entries that were missing for
  `v1.0.1`–`v1.0.3` have been written up.
- `build.sh` passes **`-file-prefix-map`** to `swiftc`, so Swift source paths
  never enter the debug info in the first place. `strip -S` (added in `v1.0.5`)
  still handles the ObjC++ half — see below.
- `install.sh` prints its messages in English. Source comments stay Korean.
- `StoreKitBridge.swift` logs in English, and **logs each step of a purchase**.

> **A purchase that stalls shows nothing on screen.** The payment sheet simply
> never appears and the button looks dead. Without a line at each step there is
> nothing to narrow the cause down with — that happened once.

## v1.0.5

**MIT license, and the build machine's paths are out of the binaries.**

- Added `LICENSE` (MIT). Without one a public repository is all-rights-reserved,
  so **nobody may legally use it**.
- `build.sh` runs **`strip -S`** on the merged archives and **fails if any
  `/Users/` string survives**.

> **DWARF embeds the absolute source path of the machine that built it**
> (`/Users/<name>/Documents/…`). These files go into a public repository, so that
> leaks the builder's username and directory layout. Only debugging symbols are
> removed — **the global symbols the linker needs stay** (measured: `/Users`
> 7 → 0, 45 global symbols unchanged, 2.2 MB → 427 KB).

> **The ObjC++ half cannot be fixed at the source.** It is compiled by the
> harness's `SConstruct`, which is not part of this repository and takes no
> arbitrary `CCFLAGS`. So it is stripped after merging, and the build fails if
> anything survives — a silent leak is only discovered after publishing.

> **Older tags still carry the paths.** Removing them would mean rewriting
> history, which would break this repository's claim that a tag points at the
> exact binary verified on a device. Clean from `v1.0.5` onward.

## v1.0.4

**The review prompt** — a Godot class named `GodotReview`, in the same plugin.

- Opens `SKStoreReviewController.requestReviewInScene:` through one `request()`
- **No Swift needed** — it is an ObjC API, so `StoreKitBridge.swift` is untouched
  (StoreKit 2's `AppStore.requestReview(in:)` is iOS 16+ and Swift-only, which
  does not fit our 15.0 floor)
- `StoreKit.framework` is already linked, so **nothing extra had to be added**

> **The scene is found through `connectedScenes`.** `delegate.window` is nil on
> Godot 4.5+ — the same trap as Game Center.

> **You cannot tell whether it appeared.** Apple caps it at three times per 365
> days and reports nothing back, so there is no return value — the caller only
> knows the ask was handed over.

## v1.0.3

**A purchase closed by a dropped connection is no longer reported as a cancel.**

When the network goes away, StoreKit answers in two different ways: drop before
the sheet appears and you get `networkError`; drop while the sheet is open and
the sheet closes with **`userCancelled`** — indistinguishable from a real cancel
by the error alone.

A cancel must stay quiet (never show an error to someone who pressed cancel), so
the bridge watches reachability separately with `NWPathMonitor` — passively, it
issues no requests. A cancel that arrives while offline is reported as
`network`. `networkError` is reported as `network` too, instead of being folded
into `purchase-error`, so the caller can show the right message. Neither case
ever produces a receipt, so offline handling in the validation path would never
have caught them.

## v1.0.2

- Diagnostics are **debug-build only** (`#ifdef DEBUG_ENABLED`). A diagnostic
  file in a shipped build is visible to the user through file sharing. Verified
  that the release library contains no call sites.
- `build.sh` deletes previous artifacts first. SCons skipped a rebuild once and
  **merged a two-day-old release library**, which cost an afternoon of chasing a
  debug-only code path. If there is no artifact, there is nothing to skip. The
  build now fails when a result is missing.

## v1.0.1

- Log the storefront. Prices appearing in USD turned out to be the signed-in
  account's region, not a bug, and there was no way to tell those apart from the
  screen alone (device: USD before sign-in → KOR after).
- Separate `user-cancelled` from real errors. A cancel arrives as a result
  **and** as an exception — the latter when the Apple ID sign-in sheet
  interrupts. Both were being folded into `purchase-error`, which made an
  ordinary cancel look like a crash. The underlying error text is now logged.
- `install.sh` clears the destination first. Overwriting left stale `.a` files
  behind, and it was no longer obvious which one was in use.

## v1.0.0

First release. Verified on device in a shipped App Store app: purchase, server
validation, restore and cancel.

- StoreKit 2 bridge (Swift) + Godot ClassDB class `GodotIap` (ObjC++)
- `initConnection` · `fetchProducts` · `requestPurchaseWithPayload` ·
  `finishTransaction` · `getAvailablePurchases` · `restorePurchases` ·
  `endConnection`
- **The JWS goes up in `purchaseToken`** — server validation hangs off that
- `build.sh` (Swift → ObjC++ → merge → two xcframeworks) and `install.sh`
