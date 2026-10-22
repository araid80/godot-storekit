# godot-storekit

**Godot 4 · iOS 인앱 결제**를 **StoreKit 2** 위에 직접 올린 것.

[`hyodotdev/godot-iap`](https://github.com/hyodotdev/godot-iap)
([OpenIAP](https://github.com/hyodotdev/openiap) 계약을 구현한 고닷 플러그인)의
**iOS 네이티브만** 갈아 끼운다. GDScript 층과 안드로이드는 그대로 둔다.

[English README](README.md)

## 왜 있나

`godot-iap`의 iOS 네이티브는 **SwiftGodot** 위에 서 있고, SwiftGodot은 Swift
파라미터 팩(`SignalWithArguments<each T>`)을 써서 **iOS 17 런타임**을 요구한다.
`GodotIap.framework`와 `SwiftGodotRuntime.framework`가 둘 다 `minos 17.0`이라,
앱에 임베드되면 **iOS 15·16 기기에서 dyld가 로드를 거부해 켜자마자 죽는다.**

이 고장은 **보이지 않는다.** 앱스토어는 `Info.plist`의 `MinimumOSVersion`만 보고
내려보내므로 15.0이라고 적어 두면 그 사람들 전원에게 배포되고, 전원이 실행 즉시
죽고, **크래시 로그는 오지 않는다.** 우리 코드가 시작되기 전에 죽기 때문이다.

**StoreKit 2 자체는 iOS 15.0+** 다. 직접 감싸면 바닥이 15로 내려온다.
(OpenIAP 패키지 자체도 15.0이다 — 17을 요구하는 것은 SwiftGodot이다.)

## 무엇을 갈아 끼우나

`godot_iap.gd`는 iOS 네이티브를 **이름으로만** 찾는다.

```gdscript
if ClassDB.class_exists("GodotIap") and ClassDB.can_instantiate("GodotIap"):
    _native_plugin = ClassDB.instantiate("GodotIap")
```

그래서 이 플러그인은 `GodotIap`이라는 ClassDB 클래스를 등록하고 같은 JSON 계약에
답한다. **그 위는 한 줄도 바뀌지 않는다.**

| | |
|---|---|
| 그대로 둔다 | `godot_iap.gd` · `IapTypes` · 게임의 결제 코드 · **안드로이드 전체** |
| 갈아 끼운다 | iOS 네이티브 하나 |
| 버린다 | `GodotIap.framework` · `SwiftGodotRuntime.framework` · `.gdextension` |

## 덤 — 별점 창 (`GodotReview`)

`SKStoreReviewController` 도 StoreKit 이고 `StoreKit.framework` 가 이미 링크돼
있어 **더 붙일 것이 없다.** 그래서 같은 플러그인에 뒀다.

```gdscript
if ClassDB.can_instantiate("GodotReview"):
    ClassDB.instantiate("GodotReview").call("request")
```

> **자체 별점 창을 그리면 안 된다.** 애플이 제공된 API 를 쓰라고 못 박아 두었다
> ("we will disallow custom review prompts").

> **띄웠는지는 알 수 없다.** 애플이 365일에 3번으로 묶고 결과를 안 알려 준다 —
> 반환값이 없고, 부르는 쪽은 "넘겼다" 까지만 안다. 언제 부를지(판 수·날짜·간격)는
> 게임이 정할 일이라 여기에 두지 않았다.

## 요구 사항

- 고닷 4 — **4.7.1**에서 만들고 출시했다
- **iOS 15.0+**, arm64 실기. 데스크톱과 시뮬레이터에는 스토어가 없다
- 앱 빌드용 Xcode와 iOS SDK
- App Store Connect에 등록된 상품, 기기에 로그인된 샌드박스 계정

**범위:** 비소모성 상품. 실제로 출시해 본 것이 그것이다. 소모성도 될 것이다
(StoreKit 2에는 소비 단계가 없다) — 시험하지 않았다. 구독 payload 경로는 있지만
**시험하지 않았다.** 아래 API 표를 본다.

## 붙이는 법

```bash
git submodule add https://github.com/araid80/godot-storekit addons/storekit
cd addons/storekit && git checkout v1.0.6 && ./install.sh
```

`install.sh`가 xcframework를 `res://ios/plugins/godotstorekit/`로 복사한다.
**엔진이 그 한 곳만 훑기 때문에** 애드온 폴더 안에 둘 수가 없다.

그다음 iOS 내보내기 프리셋에:

```ini
plugins/GodotStoreKit=true
application/min_ios_version="15.0"
```

`godot-iap`을 쓰던 프로젝트라면 **iOS 쪽만** 들어낸다 (안드로이드는 그대로).

```
addons/godot-iap/bin/ios/                     ← 통째로
addons/godot-iap/bin/godot_iap.gdextension    ← iOS 전용이라 파일째
```

## 네트워크를 쓰지 않는다

`URLSession`도, 소켓도, HTTP도 이 플러그인에는 없다. StoreKit과 고닷하고만
이야기한다.

StoreKit 2가 서명한 거래(`jwsRepresentation`)는 `purchaseToken` 칸에 그대로
실어 올린다. 안드로이드가 구글 구매 토큰을 싣는 바로 그 칸이다.
**검증은 쓰는 쪽 서버의 몫이고**, 이 플러그인은 그 방법에 관여하지 않는다.

## API

ClassDB 클래스 `GodotIap`으로 등록된다. 모든 호출은 `{"requestId": "..."}`를
즉시 돌려주고, 결과는 나중에 신호로 온다.

| 메서드 | |
|---|---|
| `initConnection(request_id)` | `Transaction.updates` 감시를 시작한다. StoreKit에는 연결 개념이 없어 언제나 성공이다 |
| `endConnection(request_id)` | 감시를 멈춘다 |
| `fetchProducts(request_json)` | → `products_fetched`의 `productsJson` |
| `requestPurchaseWithPayload(payload_json)` | `requestPurchase.apple.sku`를 읽는다 → `purchase_updated` / `purchase_error` |
| `finishTransaction(args_json)` | 둘째 인자(`isConsumable`)는 받기만 하고 쓰지 않는다. StoreKit 2에는 소비 단계가 없다 |
| `getAvailablePurchases(options_json)` | 지금 가진 것. 비면 `Transaction.all`에서 환불분을 뺀 것으로 채운다 |
| `restorePurchases(request_id)` | `AppStore.sync()` — 애플 ID 로그인 창이 뜬다 |

| 신호 | |
|---|---|
| `purchase_updated(purchase)` | 샀거나, 복원했거나, 다른 기기에서 산 것이 들어왔다 |
| `purchase_error(error)` | `user-cancelled` · `network` · `deferred` 포함 |
| `products_fetched(result)` | **비동기 결과가 전부 여기로 온다.** `method`+`requestId`로 짝을 맞춘다 |
| `connected` / `disconnected` | 계약을 맞추려고 선언만 해 둔다 |
| `promoted_product` / `subscription_billing_issue` | **선언만 있고 쏘지 않는다.** `godot_iap.gd`가 있으면 잇기 때문에 없을 수가 없다 |

결과는 배열이 아니라 사전 안의 **JSON 문자열**이다(`productsJson`,
`purchasesJson`). 우리가 고른 것이 아니라 상류 계약이다.

## 이미 값을 치른 함정들

전부 **실기에서만** 드러난다. 데스크톱에는 StoreKit이 없어 가짜 경로로 돈다.

- **UI를 띄우는 StoreKit 호출은 메인 액터에서 불러야 한다.** `product.purchase()`나
  `AppStore.sync()`를 백그라운드 `Task`에서 부르면 **창은 떠도 `await`가 재개되지
  않는다.** 취소해도 아무 답이 안 오고 화면이 잠긴 채로 남는다. 구매만 고치고
  복원을 놓쳐서 두 번 겪었다.
- **고닷 신호는 `call_deferred`로 쏜다.** Swift `Task`는 백그라운드인데 받는 쪽이
  GDScript라 그 스레드에서 스크립트가 돌게 된다. 가격 조회가 그냥 됐던 것은 운이
  좋았던 것이지 괜찮았던 것이 아니다.
- **구매 하나가 두 번 온다** — `purchase()`의 결과로 한 번, `Transaction.updates`로
  또 한 번. 거래 id로 거르지 않으면 서버 검증이 두 번 돌고 완료 알림도 두 번 뜬다.
- **칸 하나가 빠지면 복원 목록 전체가 버려진다.**
  `godot_iap.gd::_is_valid_purchase_dictionary`가 `id` `productId` `store`
  `purchaseState` `transactionDate` `quantity` `isAutoRenewing`을 전부 본다.
  `store`는 iOS에서 반드시 `"apple"`이다. `store`와 `quantity`를 빠뜨려 3건이
  통째로 0건이 됐고, 화면에는 "되찾을 구매가 없습니다"로만 보였다.
- **취소가 결과가 아니라 예외로 올 때가 있다.** 애플 ID 로그인 창이 끼어들면
  `userCancelled`가 `catch`로 온다. 둘 다 취소로 받지 않으면 평범한 취소가
  사고처럼 보인다.
- **"취소"가 늘 취소인 것도 아니다.** 결제창이 떠 있는 동안 연결이 끊기면 StoreKit은
  그것을 `userCancelled`로 준다. 그래서 `NWPathMonitor`로 연결 상태를 가만히 듣다가
  (요청을 만들지 않는다) 끊김이면 `network`로 올려보낸다. 그래야 쓰는 쪽이 사실을
  안내할 수 있다.

## 진단 기록

디버그 빌드에서만, 앱 컨테이너의 `Documents/iap.txt`에 덧붙인다.

```
[StoreKit] storefront KOR
[StoreKit] owned query — entitlements 3 · all 3 (unverified 0 · revoked 0) → 3
```

**"아무것도 없다"와 "있는데 안 넘어간다"를 가른다.** 위의 복원 함정을 잡은 것이
이 줄이다. 릴리스 빌드에는 호출부조차 들어가지 않는다 — 배포본에 진단 기록이
쌓이면 파일 공유로 사용자에게 보인다.

## 다시 빌드해야 할 때

플러그인 ABI가 달라지는 엔진 버전으로 옮길 때만 필요하다.

```bash
./build.sh [godot-ios-plugins 경로]
```

Swift 브리지 → ObjC++ 플러그인 → `libtool`로 합치기 → xcframework 두 벌(디버그·릴리스).
하네스의 `SConstruct`에 `'godotstorekit'`가 등록돼 있어야 한다. 빌드 결과에는
기계의 흔적이 남지 않는다 — 소스 경로를 바꿔 넣고 디버그 정보를 털어낸다.

## 라이선스

MIT. [LICENSE](LICENSE)를 본다.

**OpenIAP·hyodotdev와 아무 관계가 없고, 승인받거나 함께 만든 것도 아니다.**
여기 적힌 이름들은 무엇과 호환되는지를 설명하려고 쓴 것뿐이다.

[godot-ios-plugins](https://github.com/godotengine/godot-ios-plugins)(MIT)로
고닷 엔진 헤더(MIT, © Godot Engine contributors)에 맞춰 빌드했다. StoreKit은
애플의 프레임워크이고 링크할 뿐 재배포하지 않는다.
