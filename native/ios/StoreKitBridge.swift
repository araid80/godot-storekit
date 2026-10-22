//  StoreKit 2 브리지.
//
//  **왜 Swift 인가.** StoreKit 2 는 Swift 전용 API 다 (`Product`, `Transaction`).
//  Godot 플러그인 본체는 ObjC++ 이므로, 여기서 `@objc` 클래스로 감싸 넘긴다.
//
//  **왜 이 플러그인이 있나.** 원래 쓰던 OpenIAP 은 SwiftGodot 위에 서 있고,
//  SwiftGodot 은 Swift 파라미터 팩을 써서 **iOS 17 런타임**을 요구한다.
//  그 프레임워크가 앱에 임베드되면 iOS 15·16 기기에서 dyld 가 로드를 거부해
//  **켜자마자 죽는다.** StoreKit 2 자체는 iOS 15.0+ 라, 직접 감싸면 15 까지 내려간다.
//
//  결과는 전부 JSON 문자열로 넘긴다 — Godot 쪽 계약이 그렇게 돼 있다
//  (`godot_iap.gd` 의 `_call_ios_async`: 호출은 `{"requestId":…}` 를 즉시 돌려주고
//  결과는 나중에 신호로 온다).

import Foundation
import Network
import StoreKit

@objc public protocol GodotStoreKitDelegate: AnyObject {
    /// 비동기 결과 하나. `json` 에 requestId·method·success 가 들어 있다.
    func onAsyncResult(_ json: String)
    /// 구매가 갱신됐다 (구매 완료·복원·다른 기기에서 산 것).
    func onPurchaseUpdated(_ json: String)
    /// 구매가 실패했다 (취소 포함).
    func onPurchaseError(_ json: String)
}

@available(iOS 15.0, *)
@objc public final class GodotStoreKitBridge: NSObject {

    @objc public weak var delegate: GodotStoreKitDelegate?

    /// 진단을 파일로 남길 것인가. **기본은 끔** — 배포 빌드에 진단 기록이 쌓이면
    /// 파일 공유로 사용자에게 보인다. 디버그 빌드에서만 `godot_iap.mm` 이 켠다.
    @objc public static var logging: Bool = false

    /// 받아 둔 상품. `purchase()` 할 때 다시 조회하지 않으려고 들고 있는다.
    private var products: [String: Product] = [:]
    /// 끝나지 않은 트랜잭션. `finishTransaction` 이 id 로 찾는다.
    private var pending: [String: Transaction] = [:]
    /// 이미 올려보낸 트랜잭션.
    ///
    /// **구매 하나가 두 번 온다.** `purchase()` 의 결과로 한 번,
    /// `Transaction.updates` 로 또 한 번 — 둘 다 같은 트랜잭션이다.
    /// 그대로 두면 서버 검증이 두 번 돌고 "구매 완료" 도 두 번 뜬다 (실기 로그에서 확인).
    private var delivered: Set<String> = []
    private var updates: Task<Void, Never>?

    /// 지금 인터넷이 되는가. **취소와 끊김을 가르는 데 쓴다.**
    ///
    /// 결제창이 떠 있는 동안 연결이 끊기면 StoreKit 은 그것을 `userCancelled` 로 준다 —
    /// 사용자가 누른 취소와 **구별이 안 된다**. 오류만으로는 못 가르므로 상태를 따로 본다.
    /// `NWPathMonitor` 는 가만히 듣고만 있어 요청을 만들지 않는다.
    private let monitor = NWPathMonitor()
    private var online = true

    @objc public override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.online = (path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "godot.storekit.net"))
    }

    // ── 연결 ────────────────────────────────────────────────

    /// StoreKit 2 에는 **연결이라는 개념이 없다.** 그래도 계약을 맞춰 즉시 성공으로 답한다.
    ///
    /// 대신 여기서 **갱신 감시를 시작한다.** 앱 밖에서 일어난 구매(다른 기기, 가족 공유,
    /// 앱이 꺼져 있는 동안 승인된 결제)가 이 줄로 들어온다 — 안 걸면 그런 구매가 조용히 샌다.
    @objc public func initConnection(_ requestId: String) {
        if updates == nil {
            updates = Task.detached(priority: .background) { [weak self] in
                for await update in Transaction.updates {
                    await self?.handle(update, notify: true)
                }
            }
        }
        reply(requestId, "initConnection", ["success": true, "connected": true])
    }

    @objc public func endConnection(_ requestId: String) {
        updates?.cancel()
        updates = nil
        reply(requestId, "endConnection", ["success": true])
    }

    // ── 상품 ────────────────────────────────────────────────

    /// `ids` 로 상품을 물어본다. 화면에 띄울 가격은 **스토어가 준 문자열 그대로** 쓴다
    /// (`displayPrice` 가 통화 기호·자릿수·기호 위치까지 그 나라 규칙으로 맞춰 준다).
    @objc public func fetchProducts(_ requestId: String, ids: [String]) {
        Task {
            do {
                // **어느 나라 스토어로 물어봤는지 남긴다.**
                // 가격 통화는 우리가 정하는 게 아니라 **로그인된 계정의 지역**이 정한다.
                // 화면에 USD 가 뜨면 코드 문제인지 계정 지역인지 이 줄로 갈린다.
                let front = await Storefront.current
                Self.note("storefront \(front?.countryCode ?? "none")"
                    + " (none = not signed in, so the device default region)")

                let got = try await Product.products(for: ids)
                for p in got { products[p.id] = p }
                let list = got.map { p -> [String: Any] in
                    [
                        "id": p.id,
                        "title": p.displayName,
                        "description": p.description,
                        "displayPrice": p.displayPrice,
                        "display_price": p.displayPrice,   // Godot 쪽이 이 이름으로 읽는다
                        "currency": p.priceFormatStyle.currencyCode,
                        "platform": "ios",
                    ]
                }
                // **`productsJson` 이다** — Godot 쪽이 배열이 아니라 **JSON 문자열**로 읽는다
                // (`signal_result.get("productsJson", "[]")`). 이름이나 형을 바꾸면
                // 조용히 빈 목록이 되고, 화면에는 "가격이 안 뜬다" 로만 보인다.
                reply(requestId, "fetchProducts",
                      ["success": true, "productsJson": Self.json(list)])
            } catch {
                reply(requestId, "fetchProducts",
                      ["success": false, "code": "query-product",
                       "error": "\(error)"])
            }
        }
    }

    // ── 구매 ────────────────────────────────────────────────

    /// **결과를 여기서 돌려주지 않는다.** 산 것은 `onPurchaseUpdated`,
    /// 취소·실패는 `onPurchaseError` 로 간다 — Godot 쪽이 그렇게 듣고 있다.
    @objc public func requestPurchase(_ sku: String) {
        let requestId = "purchase"
        // **여기서 멎으면 화면에는 아무 일도 안 일어난다.** 결제창이 떠야 하는데
        // 안 뜨면 사용자는 버튼이 죽은 것으로 본다. 그래서 단계마다 남긴다 —
        // 한 번 이 자리에서 아무 기록도 없이 멈춰서 원인을 좁힐 수가 없었다.
        Self.note("purchase requested \(sku) · \(products.count) product(s) cached")
        // **메인 액터에서 돌아야 한다.** `purchase()` 는 결제창을 띄우는데,
        // 백그라운드에서 부르면 창은 떠도 **await 가 재개되지 않는다** —
        // 취소를 눌러도 아무 답이 안 와서 진행 표시가 30초 뒤 스스로 걷혔다 (실기).
        Task { @MainActor in
            // **`??` 로 쓰면 안 된다.** 오른쪽이 `@autoclosure` 라 `await` 를 못 넣는다.
            var found = products[sku]
            if found == nil {
                found = (try? await Product.products(for: [sku]))?.first
            }
            guard let product = found else {
                Self.note("product not found \(sku)")
                fail(sku, "query-product", "상품을 못 찾았다: \(sku)")
                reply(requestId, "requestPurchase", ["success": false])
                return
            }
            products[sku] = product
            do {
                Self.note("presenting payment sheet \(sku)")
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    Self.note("purchase succeeded \(sku)")
                    await handle(verification, notify: true)
                    reply(requestId, "requestPurchase", ["success": true])
                case .userCancelled:
                    // **취소는 오류로 찍되 사고가 아니다.** 부르는 쪽이 진행 표시를
                    // 걷으려면 반드시 답이 와야 한다 — 안 오면 화면이 잠긴 채로 남는다.
                    fail(sku, "user-cancelled", "사용자가 취소했다")
                    reply(requestId, "requestPurchase", ["success": false])
                case .pending:
                    // 가족 승인 대기 등. 아직 준 게 아니다.
                    fail(sku, "deferred", "승인 대기 중이다")
                    reply(requestId, "requestPurchase", ["success": false])
                @unknown default:
                    fail(sku, "service-error", "모르는 결과")
                    reply(requestId, "requestPurchase", ["success": false])
                }
            } catch {
                // **예외로 오는 취소를 따로 가른다.** `.userCancelled` 는 결과로도 오고
                // 예외로도 온다 — 로그인 창이 끼어들면 이쪽이다.
                // 그때는 **로그인 뒤 다시 눌러야** 산다. 사고가 아니다.
                // **네트워크 오류를 따로 가른다.** 인터넷이 없으면 결제창이
                // 열리기도 전에 여기로 온다 — 영수증이 없으니 검증 쪽 오프라인
                // 처리에는 영영 안 걸린다. 부르는 쪽이 같은 안내를 띄우게 한다.
                var code = "purchase-error"
                if let sk = error as? StoreKitError {
                    switch sk {
                    // **끊겨서 닫힌 것을 취소로 넘기지 않는다.** 사용자는 아무것도
                    // 안 눌렀는데 조용히 끝나면 앱이 먹은 것으로 보인다 (실기 지적).
                    case .userCancelled: code = online ? "user-cancelled" : "network"
                    case .networkError: code = "network"
                    default: break
                    }
                }
                Self.note("purchase threw — \(error)")
                fail(sku, code, "\(error)")
                reply(requestId, "requestPurchase", ["success": false])
            }
        }
    }

    // ── 소유 확인 · 복원 ─────────────────────────────────────

    /// 지금 가진 것. 비소모성만 팔므로 `currentEntitlements` 가 곧 소유 목록이다.
    @objc public func getAvailablePurchases(_ requestId: String) {
        Task {
            var list: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if let dict = await self.dictionary(for: result, finishable: false) {
                    list.append(dict)
                }
            }
            // **비면 `Transaction.all` 도 훑는다.**
            //
            // `currentEntitlements` 는 **지금 소유한 것**만 준다. 상품이 App Store Connect 에
            // **소모성으로 등록돼 있으면 여기 절대 안 나온다** — 사서 검증까지 통과해도
            // 복원할 게 없다고 나온다 (실기에서 그랬다).
            //
            // `all` 은 지난 거래 전부라 **환불·취소된 것이 섞인다.** 그래서
            // `revocationDate` 가 있는 것은 반드시 거른다 — 안 그러면
            // 환불받은 사람에게 물건을 돌려주게 된다.
            let entitled = list.count

            // **셋을 따로 센다.** "아무것도 없다" 와 "있는데 검증이 안 된다" 는
            // 완전히 다른 문제인데 결과만 보면 똑같이 0건으로 보인다.
            var allCount = 0
            var unverified = 0
            var revoked = 0
            var fromAll = false
            for await result in Transaction.all {
                allCount += 1
                guard case .verified(let tx) = result else { unverified += 1; continue }
                if tx.revocationDate != nil { revoked += 1; continue }
                if !list.isEmpty { continue }
                if list.contains(where: { ($0["productId"] as? String) == tx.productID }) { continue }
                if let dict = await self.dictionary(for: result, finishable: false) {
                    list.append(dict)
                    fromAll = true
                }
            }

            Self.note("owned query — entitlements \(entitled) · all \(allCount)"
                + " (unverified \(unverified) · revoked \(revoked)) → \(list.count)")

            // 여기도 JSON 문자열이다 (`purchasesJson`).
            reply(requestId, "getAvailablePurchases",
                  ["success": true, "purchasesJson": Self.json(list),
                   "source": fromAll ? "all" : "entitlements"])
        }
    }

    /// **스토어와 한 번 맞춘다.** 앱을 지웠다 다시 깐 뒤에도 옛 구매가 나오게 하려면
    /// 이걸 먼저 불러야 한다 (`currentEntitlements` 만으로는 안 나올 수 있다).
    @objc public func restorePurchases(_ requestId: String) {
        // **여기도 메인 액터다.** `AppStore.sync()` 는 애플 ID 로그인 창을 띄운다 —
        // 구매와 같은 이유로 백그라운드에서 부르면 창은 떠도 await 가 안 돌아온다.
        // 구매만 고치고 이쪽을 놓쳐서 복원이 아무 답 없이 멈췄다 (실기).
        Task { @MainActor in
            do {
                try await AppStore.sync()
                reply(requestId, "restorePurchases", ["success": true])
            } catch {
                // 취소해도 여기로 온다. 실패로 두되 사유를 남긴다.
                reply(requestId, "restorePurchases",
                      ["success": false, "code": "sync-error", "error": "\(error)"])
            }
        }
    }

    // ── 마무리 ──────────────────────────────────────────────

    /// **`consume` 은 무시한다.** 우리가 파는 것은 전부 영구 소유라 소비하면 안 된다.
    /// StoreKit 2 에는 소비 개념이 없고 `finish()` 뿐이라 원래 안전하지만,
    /// 인자를 받는 것은 Godot 쪽 계약을 맞추기 위해서다.
    @objc public func finishTransaction(_ requestId: String, transactionId: String) {
        Task {
            if let tx = pending.removeValue(forKey: transactionId) {
                await tx.finish()
                delivered.remove(transactionId)
                reply(requestId, "finishTransaction", ["success": true])
                return
            }
            // 이미 끝났거나 우리가 모르는 것. 다시 끝낼 수는 없지만 실패도 아니다.
            reply(requestId, "finishTransaction", ["success": true])
        }
    }

    // ── 안쪽 ────────────────────────────────────────────────

    /// 트랜잭션 하나를 받아들인다.
    ///
    /// **검증 실패한 것은 올려보내지 않는다.** StoreKit 이 서명을 못 믿겠다고 한 것이라,
    /// 그걸 통과시키면 서버 검증을 붙인 뜻이 없어진다.
    private func handle(_ result: VerificationResult<Transaction>, notify: Bool) async {
        guard let dict = await dictionary(for: result, finishable: true) else { return }
        guard let id = dict["id"] as? String else { return }
        // **같은 트랜잭션은 한 번만 올려보낸다.**
        // 다른 기기에서 산 것은 id 가 다르므로 그건 그대로 들어온다.
        if delivered.contains(id) { return }
        delivered.insert(id)
        if notify { delegate?.onPurchaseUpdated(Self.json(dict)) }
    }

    /// 트랜잭션을 Godot 이 읽는 모양으로 바꾼다.
    ///
    /// **`purchaseToken` 에 JWS 를 넣는다.** 안드로이드는 같은 칸에 구글의 purchase token 이
    /// 오고, 서버가 앞글자로 가린다 — 그래서 칸 이름이 플랫폼마다 다르지 않다.
    /// **JWS 가 서버 검증의 전부다.** 이게 비면 물건을 줄 근거가 없어진다.
    private func dictionary(for result: VerificationResult<Transaction>,
                            finishable: Bool) async -> [String: Any]? {
        guard case .verified(let tx) = result else { return nil }
        let id = String(tx.id)
        if finishable { pending[id] = tx }
        // **칸이 하나라도 빠지면 배치가 통째로 버려진다.**
        // `godot_iap.gd::_is_valid_purchase_dictionary` 가 전부 검사하고,
        // 한 항목만 어긋나도 `_validated_purchase_batch` 가 목록 전체를 실패로 돌린다 —
        // 화면에는 "되찾을 구매가 없습니다" 로만 보인다.
        // 실기에서 StoreKit 은 3건을 줬는데 Godot 은 0건으로 받았고,
        // 빠진 것은 `store` 와 `quantity` 두 칸이었다.
        return [
            "id": id,
            "transactionId": id,
            "productId": tx.productID,
            "purchaseToken": result.jwsRepresentation,   // ← 서버가 검증하는 값
            "purchaseState": "purchased",
            "transactionDate": tx.purchaseDate.timeIntervalSince1970 * 1000,
            "store": "apple",                            // iOS 는 이 값이어야 통과한다
            "quantity": tx.purchasedQuantity,
            "platform": "ios",
            "isAutoRenewing": false,
        ]
    }

    private func fail(_ sku: String, _ code: String, _ message: String) {
        delegate?.onPurchaseError(Self.json([
            "code": code, "message": message, "productId": sku, "platform": "ios",
        ]))
    }

    /// 비동기 결과 한 건. **`requestId` 와 `method` 가 반드시 실려야 한다** —
    /// Godot 쪽이 그 둘로 어느 호출의 답인지 맞춘다 (`_ios_async_result_key`).
    private func reply(_ requestId: String, _ method: String, _ payload: [String: Any]) {
        var out = payload
        out["requestId"] = requestId
        out["method"] = method
        delegate?.onAsyncResult(Self.json(out))
    }

    /// 진단 한 줄. **게임의 결제 로그(`iap.txt`)에 그대로 이어 쓴다** —
    /// 따로 파일을 만들면 꺼내 오는 절차가 하나 더 늘고, 시간 순서도 어긋난다.
    ///
    /// iOS 는 `print()` 가 devicectl 콘솔로 안 나오고, Godot 신호로 올려 보내려면
    /// GDScript 쪽 계약을 건드려야 해서 이 길이 가장 싸다.
    private static func note(_ line: String) {
        guard logging else { return }
        guard let dir = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("iap.txt")
        guard let data = ("[StoreKit] " + line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
