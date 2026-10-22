# godot-storekit

In-app purchase for **Godot 4 on iOS**, built directly on **StoreKit 2**.

It is a drop-in replacement for the **iOS native half** of
[`hyodotdev/godot-iap`](https://github.com/hyodotdev/godot-iap) (the Godot plugin
that implements the [OpenIAP](https://github.com/hyodotdev/openiap) contract).
The GDScript layer and the whole Android side stay exactly as they are.

[한국어 README](README.ko.md)

## Why this exists

`godot-iap`'s iOS native is built on **SwiftGodot**, which uses Swift parameter
packs (`SignalWithArguments<each T>`) and therefore requires an **iOS 17
runtime**. `GodotIap.framework` and `SwiftGodotRuntime.framework` are both
`minos 17.0`, so once they are embedded, **dyld refuses to load them on iOS 15
and 16 and the app dies at launch.**

That failure is invisible to you: the App Store ships by `MinimumOSVersion` in
`Info.plist`, so if you declare 15.0 the build goes out to every one of those
users, every one of them dies instantly, and **no crash report reaches you**
because the process never gets as far as your code.

**StoreKit 2 itself is iOS 15.0+.** Wrapping it directly brings the floor back
down to 15. (OpenIAP's own package is 15.0 too — the 17 comes from SwiftGodot.)

## What it replaces

`godot_iap.gd` finds its iOS native purely by class name:

```gdscript
if ClassDB.class_exists("GodotIap") and ClassDB.can_instantiate("GodotIap"):
    _native_plugin = ClassDB.instantiate("GodotIap")
```

So this plugin registers a ClassDB class called `GodotIap` and answers the same
JSON contract. **Nothing above it changes.**

| | |
|---|---|
| Unchanged | `godot_iap.gd` · `IapTypes` · your purchase code · **all of Android** |
| Replaced | the iOS native, and only that |
| Dropped | `GodotIap.framework` · `SwiftGodotRuntime.framework` · the `.gdextension` |

## Bonus — the review prompt (`GodotReview`)

`SKStoreReviewController` is StoreKit too, and `StoreKit.framework` is already
linked, so there was nothing extra to add. It lives in the same plugin.

```gdscript
if ClassDB.can_instantiate("GodotReview"):
    ClassDB.instantiate("GodotReview").call("request")
```

**Do not draw your own rating dialog.** Apple requires the provided API —
"we will disallow custom review prompts."

**You cannot tell whether it appeared.** Apple caps it at three times per 365
days and reports nothing back, so `request()` returns nothing: the caller only
knows the ask was handed over. *When* to ask — plays, days, spacing — is the
game's decision and is deliberately not in here.

## Requirements

- Godot 4 — developed and shipped against **4.7.1**
- **iOS 15.0+**, arm64 device builds (StoreKit has no desktop/simulator store)
- Xcode with the iOS SDK, for building the app
- Products registered in App Store Connect, and a sandbox account on the device

**Scope:** non-consumable products, which is what it has shipped with.
Consumables should work (StoreKit 2 has no consume step) but are untested.
The subscription payload path exists and is **untested** — see the API table.

## Install

```bash
git submodule add https://github.com/araid80/godot-storekit addons/storekit
cd addons/storekit && git checkout v1.0.6 && ./install.sh
```

`install.sh` copies the xcframeworks into `res://ios/plugins/godotstorekit/`,
because the engine only scans that one directory — a plugin cannot live inside
its own addon folder.

Then, in the iOS export preset:

```ini
plugins/GodotStoreKit=true
application/min_ios_version="15.0"
```

If you are coming from `godot-iap`, remove **only its iOS half** (leave Android
alone):

```
addons/godot-iap/bin/ios/                     ← the whole directory
addons/godot-iap/bin/godot_iap.gdextension    ← iOS-only, delete the file
```

## It never touches the network

There is no `URLSession`, no socket, no HTTP anywhere in this plugin. It talks
to StoreKit and to Godot, and to nothing else.

StoreKit 2's signed transaction (`jwsRepresentation`) is handed up in the
`purchaseToken` field, the same slot Android uses for the Google purchase token.
**Validating it is your server's job** — this plugin takes no position on how.

## API

Registered as ClassDB class `GodotIap`. Every call returns immediately with
`{"requestId": "..."}`; results arrive later on a signal.

| Method | |
|---|---|
| `initConnection(request_id)` | starts watching `Transaction.updates`. StoreKit has no connection, so this always succeeds |
| `endConnection(request_id)` | stops watching |
| `fetchProducts(request_json)` | → `products_fetched` with `productsJson` |
| `requestPurchaseWithPayload(payload_json)` | reads `requestPurchase.apple.sku` → `purchase_updated` / `purchase_error` |
| `finishTransaction(args_json)` | the second argument (`isConsumable`) is accepted and ignored; StoreKit 2 has no consume step |
| `getAvailablePurchases(options_json)` | current entitlements, falling back to `Transaction.all` minus revoked |
| `restorePurchases(request_id)` | `AppStore.sync()` — shows the Apple ID sign-in sheet |

| Signal | |
|---|---|
| `purchase_updated(purchase)` | bought, restored, or picked up from another device |
| `purchase_error(error)` | includes `user-cancelled`, `network`, `deferred` |
| `products_fetched(result)` | **every** async result comes back here, matched by `method` + `requestId` |
| `connected` / `disconnected` | declared for contract compatibility |
| `promoted_product` / `subscription_billing_issue` | **declared but never emitted.** `godot_iap.gd` connects them if they exist, so they have to exist |

Results are JSON **strings** inside the dictionary (`productsJson`,
`purchasesJson`), not arrays. That is the upstream contract, not a choice.

## Gotchas this plugin already pays for

All of these only show up on a real device — desktop has no StoreKit and runs a
fake path.

- **StoreKit calls that present UI must run on the main actor.** Call
  `product.purchase()` or `AppStore.sync()` from a background `Task` and the
  sheet appears but **the `await` never resumes** — cancel it and nothing comes
  back, so your UI stays locked forever. Purchase was fixed first and restore
  was missed, so this one cost two rounds.
- **Emit Godot signals with `call_deferred`.** Swift `Task`s are off the main
  thread, and the receiver is GDScript, which would then run script on that
  thread. Price fetching worked by luck before this, not by design.
- **One purchase arrives twice** — once as the result of `purchase()` and once
  through `Transaction.updates`. Filter by transaction id or your server
  verifies twice and the user sees two confirmations.
- **One missing field throws away the whole restore list.**
  `godot_iap.gd::_is_valid_purchase_dictionary` requires `id`, `productId`,
  `store`, `purchaseState`, `transactionDate`, `quantity` and `isAutoRenewing`;
  `store` must be `"apple"` on iOS. Omitting `store` and `quantity` turned 3
  restored purchases into 0, and all the user saw was "nothing to restore".
- **A cancel can arrive as an exception, not a result.** When the Apple ID
  sign-in sheet interrupts, `userCancelled` comes through the `catch`. Treat
  both as a cancel, or an ordinary cancel looks like a crash.
- **"Cancelled" does not always mean cancelled.** If the connection drops while
  the sheet is open, StoreKit reports `userCancelled`. This plugin watches
  reachability with `NWPathMonitor` (passively — it issues no requests) and
  reports `network` instead, so your app can say something true.

## Debug log

In debug builds only, the bridge appends to `Documents/iap.txt` in the app
container:

```
[StoreKit] storefront KOR
[StoreKit] owned query — entitlements 3 · all 3 (unverified 0 · revoked 0) → 3
```

It separates "there is nothing" from "there is something and it isn't getting
through", which is what caught the restore bug above. Release builds don't even
contain the call sites — shipping a diagnostic file would expose it to the user
through file sharing.

## Rebuilding

Only needed when you move to an engine version with a different plugin ABI.

```bash
./build.sh [path to godot-ios-plugins]
```

Swift bridge → ObjC++ plugin → `libtool` merge → two xcframeworks (debug and
release). The harness's `SConstruct` must list `'godotstorekit'` as a plugin.
Builds are path-clean: source paths are remapped and debug info is stripped, so
the artifacts carry nothing about the machine that built them.

## License

MIT — see [LICENSE](LICENSE).

**Not affiliated with, endorsed by, or produced by OpenIAP or hyodotdev.** Those
names appear here only to describe what this plugin is compatible with.

Built with [godot-ios-plugins](https://github.com/godotengine/godot-ios-plugins)
(MIT) against Godot Engine headers (MIT, © Godot Engine contributors). StoreKit
is Apple's framework and is linked, not redistributed.
