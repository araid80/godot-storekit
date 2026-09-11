# 바뀐 것

버전은 `MAJOR.MINOR.PATCH` 로 붙인다.

> **태그를 옮기지 않는다.** 한 번 붙인 태그가 가리키는 커밋은 영원히 그대로다.
> 고칠 게 생기면 **다음 번호를 새로 붙인다.**

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
