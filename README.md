# godot-storekit

Godot 4 iOS 결제 — **StoreKit 2**. `hyodotdev/openiap` 의 **iOS 네이티브만** 갈아 끼운다.

## 왜 있나

OpenIAP 의 iOS 쪽은 **SwiftGodot** 위에 서 있고, SwiftGodot 은 Swift **파라미터 팩**
(`SignalWithArguments<each T>`)을 써서 **iOS 17 런타임**을 요구한다.
그 프레임워크(`GodotIap.framework` · `SwiftGodotRuntime.framework`, 둘 다 minos 17.0)가
앱에 임베드되면 **iOS 15·16 기기에서 dyld 가 로드를 거부해 켜자마자 죽는다.**

앱스토어는 `Info.plist` 의 `MinimumOSVersion` 만 보고 내려보내므로,
14.0 이라고 적어 두면 그 사람들에게 배포되고 **전원이 실행 즉시 죽는다.**

**StoreKit 2 자체는 iOS 15.0+** 다. 직접 감싸면 15 까지 내려간다.
(OpenIAP **자체** 패키지도 이미 15.0 이다 — 17 을 요구하는 것은 SwiftGodot 이다.)

## 무엇을 갈아 끼우나

OpenIAP 의 `godot_iap.gd`(2,000줄 넘는 GDScript)는 iOS 네이티브를 이렇게 잡는다:

```gdscript
if ClassDB.class_exists("GodotIap") and ClassDB.can_instantiate("GodotIap"):
    _native_plugin = ClassDB.instantiate("GodotIap")
```

**이름만 맞으면 된다.** 그래서 이 플러그인은 `GodotIap` 이라는 ClassDB 클래스를 등록한다.

| | |
|---|---|
| 그대로 둔다 | `godot_iap.gd` · `IapTypes` · 게임의 결제 코드 · **안드로이드 전체** |
| 갈아 끼운다 | iOS 네이티브 하나 |
| 버린다 | `GodotIap.framework` · `SwiftGodotRuntime.framework` · `.gdextension` |

## 붙이는 법

```bash
git submodule add https://github.com/araid80/godot-storekit addons/storekit
cd addons/storekit && git checkout v1.0.0 && ./install.sh
```

그다음 `export_presets.cfg` 의 iOS 프리셋:

```ini
plugins/GodotStoreKit=true
application/min_ios_version="15.0"
```

OpenIAP 을 쓰던 프로젝트라면 **iOS 쪽만** 들어낸다 (안드로이드는 그대로 둔다):

```
addons/godot-iap/bin/ios/          ← 통째로
addons/godot-iap/bin/godot_iap.gdextension   ← iOS 전용이라 파일째
```

## 다시 빌드해야 할 때

엔진 버전을 올렸을 때만 필요하다. `./build.sh` 가 전부 한다
(Swift → ObjC++ → `libtool` 로 합치기 → xcframework 두 벌).
하네스(`godot-ios-plugins`)의 `SConstruct` 에 `'godotstorekit'` 를 넣어 둬야 한다.

## 두 번 이상 당한 것

전부 **실기에서만** 드러난 것들이다. 데스크톱에는 StoreKit 이 없어 가짜 경로로 돈다.

- **UI 를 띄우는 StoreKit 호출은 메인 액터에서 불러야 한다.**
  `product.purchase()` 와 `AppStore.sync()` 를 백그라운드 `Task` 에서 부르면
  **창은 떠도 `await` 가 재개되지 않는다.** 취소해도 아무 답이 안 오고 화면이 잠긴다.
  구매만 고치고 복원을 놓쳐서 두 번 겪었다
- **Godot 신호는 `call_deferred` 로 쏜다.** Swift 의 `Task` 는 백그라운드인데
  신호를 받는 쪽이 GDScript 라 그 스레드에서 스크립트가 돌게 된다.
  가격 조회가 그냥 됐던 것은 운이 좋았던 것이지 괜찮았던 것이 아니다
- **구매 하나가 두 경로로 온다** — `purchase()` 의 결과와 `Transaction.updates`.
  트랜잭션 id 로 거르지 않으면 서버 검증이 두 번 돌고 완료 알림도 두 번 뜬다
- **복원 항목은 칸이 하나만 빠져도 목록 전체가 버려진다.**
  `godot_iap.gd::_is_valid_purchase_dictionary` 가 `id` `productId` `store`
  `purchaseState` `transactionDate` `quantity` `isAutoRenewing` 을 전부 본다.
  `store` 는 iOS 에서 반드시 `"apple"` 이다.
  `store`·`quantity` 를 빠뜨려 **3건이 통째로 0건**이 됐고,
  화면에는 "되찾을 구매가 없습니다" 로만 보였다
- **결과 키가 `products`/`purchases` 가 아니라 `productsJson`/`purchasesJson`** 이고
  배열이 아니라 **JSON 문자열**이다. 틀리면 조용히 빈 목록이 된다
- **비동기 결과는 전부 `products_fetched` 신호로 나간다.** 이름이 어울리지 않지만
  그게 계약이다 — 받는 쪽이 `method`+`requestId` 로 짝을 맞춘다

## 진단

`getAvailablePurchases` 가 셀 때마다 앱의 결제 로그(`user://iap.txt`)에 한 줄 남긴다:

```
[StoreKit] 소유 조회 — entitlements 3 · all 3 (검증실패 0 · 환불 0) → 3건
```

**"아무것도 없다" 와 "있는데 안 넘어간다" 를 가른다.** 이 줄이 위 마지막 함정을 잡았다.
