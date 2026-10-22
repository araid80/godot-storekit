# 바뀐 것

버전은 `MAJOR.MINOR.PATCH` 로 붙인다.

> **태그를 옮기지 않는다.** 한 번 붙인 태그가 가리키는 커밋은 영원히 그대로다.
> 고칠 게 생기면 **다음 번호를 새로 붙인다.**

---

## v1.0.5

**MIT 라이선스**와 **빌드 경로 제거.** 코드 동작은 한 줄도 안 바뀐다.

- `LICENSE` 를 넣었다. 공개 저장소에 라이선스가 없으면 기본 저작권이라
  **아무도 합법적으로 쓸 수 없다**
- `build.sh` 가 합친 뒤 **`strip -S`** 로 디버그 정보를 떼어낸다

> **DWARF 에 빌드한 기계의 절대 경로가 박힌다** (`/Users/<이름>/Documents/...`).
> 공개 저장소에 올라가는 파일이라 그대로 두면 사용자 이름과 디렉터리 구조가 드러난다.
> 지우는 것은 디버그 심볼뿐이라 **링크에 필요한 전역 심볼은 남는다**
> (실측: `/Users` 7 → 0, 전역 심볼 45개 그대로, 2.2MB → 427KB).

> **원천(컴파일 플래그)에서는 못 막는다.** ObjC++ 쪽은 하네스의 `SConstruct` 가
> 컴파일하는데 그건 이 저장소가 아니고 임의 `CCFLAGS` 를 안 받는다.
> 그래서 합친 뒤에 떼고, **남으면 `build.sh` 가 실패시킨다** —
> 조용히 새어 나가면 공개된 뒤에야 알게 된다 (strip 을 빼서 잡히는 것을 확인했다).

> **옛 태그(v1.0.0~v1.0.4)의 디버그 아카이브에는 경로가 그대로 있다.**
> 지우려면 이력을 다시 써야 하는데, 그러면 "그 태그가 그때 실기에서 검증된 바로
> 그 바이너리" 라는 이 저장소의 주장이 깨진다. v1.0.5 부터 깨끗하다.

실기 경로가 아니라 빌드 산출물만 바뀌었으므로 **다시 검증하지 않았다.**
대신 ipa 를 구워 `GodotIap` · `GodotReview` · `SKStoreReviewController` ·
Swift 브리지가 전부 링크되는 것을 확인했다 (앱 바이너리에 우리 기계 경로 0개).

---

## v1.0.4

**별점 창**을 같은 플러그인에 넣었다 — Godot 클래스 `GodotReview`.

- `SKStoreReviewController.requestReviewInScene:` 하나를 `request()` 로 연다
- **Swift 가 필요 없다** — ObjC API 라 `StoreKitBridge.swift` 를 안 건드린다
  (StoreKit 2 의 `AppStore.requestReview(in:)` 은 iOS 16+ · Swift 전용이라
  우리 바닥 15.0 과 안 맞는다)
- `StoreKit.framework` 가 이미 링크돼 있어 **더 붙일 것이 없다**

> **씬은 `connectedScenes` 에서 직접 찾는다.** `delegate.window` 는 Godot 4.5+ 에서
> nil 이다 (Game Center 에서 겪은 것과 같은 함정).

> **띄웠는지는 알 수 없다.** 애플이 365일에 3번으로 묶고 결과를 안 알려 준다.
> 그래서 반환값이 없다 — 부르는 쪽은 "넘겼다" 까지만 안다.

---

## v1.0.3

**끊겨서 닫힌 결제를 취소로 넘기지 않는다.**

인터넷이 없을 때 StoreKit 이 두 가지로 답한다 — 결제창이 뜨기 **전**에 끊기면
`networkError`, 창이 떠 있는 **도중**에 끊기면 창이 닫히면서 **`userCancelled`** 다.
뒤쪽은 사람이 누른 취소와 오류만으로는 구별이 안 된다.

- `NWPathMonitor` 로 연결 상태를 따로 듣는다. 취소가 왔는데 그 순간 오프라인이면
  **끊김으로 본다** — 취소를 시끄럽게 만들 수는 없으므로(누른 사람에게 오류를 띄우면 안 된다)
- `networkError` 도 `purchase-error` 와 갈라 **`network`** 로 올려보낸다 —
  그래야 부르는 쪽이 안내를 띄울 수 있다

```
구매 실패 network userCancelled   ← StoreKit 은 취소라고 했지만
오프라인 안내 — 결제 전            ← 끊김으로 바로잡아 안내까지 갔다
```

---

## v1.0.2

**진단은 디버그 빌드에서만** · `build.sh` 가 먼저 지운다.

- `[StoreKit]` 진단을 파일로 남기는 것을 기본으로 끄고 **디버그 빌드의 `.mm` 에서만**
  켠다 (`#ifdef DEBUG_ENABLED`). 배포본에 진단이 쌓이면 **파일 공유로 사용자에게 보인다**
- `build.sh` 가 **먼저 지운다.** scons 가 재빌드를 건너뛰어 **릴리스만 이틀 전 것이
  그대로 합쳐진 적이 있다.** 산출물이 없으면 건너뛸 수가 없고, 결과가 없으면 실패시킨다

---

## v1.0.1

**스토어프론트와 구매 예외를 로그에 남긴다.**

- 통화는 우리가 정하는 게 아니라 **로그인된 계정의 지역**이 정한다. 코드 문제인지
  계정 지역인지 화면만 봐서는 구별이 안 돼 스토어프론트를 찍는다
  (실기: 로그인 전 USD → 로그인 후 KOR)
- **구매 취소는 결과로도 오고 예외로도 온다** — 로그인 창이 끼어들면 이쪽이다.
  예전에는 둘이 `purchase-error` 로 뭉뚱그려져 사고처럼 보였다
- `install.sh` 가 먼저 비운다. 덮어쓰기만 하면 예전 빌드의 `.a` 가 남아
  어느 것이 실제로 쓰이는지 헷갈린다

---

## v1.0.0

첫 배포판. **TESSERAVE 실기(iPhone)에서 구매·검증·복원·취소를 전부 확인한 코드다.**

- StoreKit 2 브리지 (Swift) + Godot 클래스 `GodotIap` (ObjC++)
- `initConnection` · `fetchProducts` · `requestPurchaseWithPayload` ·
  `finishTransaction` · `getAvailablePurchases` · `restorePurchases` · `endConnection`
- **JWS 를 `purchaseToken` 에 그대로 싣는다** — 서버 검증이 여기 걸려 있다
- `build.sh` (Swift → ObjC++ → 합치기 → xcframework 두 벌) · `install.sh`

확인된 것:

```
가격 8/8 개 도착
영수증 통과  ...pack.meadow          ← 구매 + JWS 서버 검증
구매 실패 user-cancelled             ← 취소가 즉시 보고된다
복원 끝 — 3개                        ← 심사 의무 항목
```

### 게임 쪽에서 할 일

`export_presets.cfg` 에 `plugins/GodotStoreKit=true` 와
`min_ios_version="15.0"`. OpenIAP 을 쓰던 프로젝트는 iOS 쪽을 들어낸다 (README).
**GDScript 는 한 줄도 안 고친다.**
