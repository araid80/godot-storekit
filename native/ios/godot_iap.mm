#include "godot_iap.h"

#include "core/io/json.h"
#import <Foundation/Foundation.h>
#import "GodotStoreKit-Swift.h"

/* Swift 가 결과를 돌려줄 때 쓰는 통로.
 *
 * **약하게 잡는다.** Godot 쪽 객체가 먼저 사라질 수 있고, 그때 강한 참조가 남아 있으면
 * 죽은 객체에 신호를 쏘게 된다. */
@interface GodotIapRelay : NSObject <GodotStoreKitDelegate>
@property(nonatomic, assign) GodotIap *owner;
@end

@implementation GodotIapRelay
- (void)onAsyncResult:(NSString *)json {
	if (_owner) _owner->_deliver_async(String::utf8([json UTF8String]));
}
- (void)onPurchaseUpdated:(NSString *)json {
	if (_owner) _owner->_deliver_purchase(String::utf8([json UTF8String]));
}
- (void)onPurchaseError:(NSString *)json {
	if (_owner) _owner->_deliver_error(String::utf8([json UTF8String]));
}
@end

/* 브리지와 통로를 한 덩이로 들고 있는다. */
struct GodotIapImpl {
	GodotStoreKitBridge *bridge = nil;
	GodotIapRelay *relay = nil;
};

static Dictionary _parse(const String &p_json) {
	Variant parsed = JSON::parse_string(p_json);
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
}

/* **호출은 즉시 requestId 를 돌려준다.** 결과는 나중에 신호로 온다 —
 * `godot_iap.gd::_call_ios_async` 가 그 둘을 짝지어 기다린다.
 * 이 문자열이 비면 그쪽은 "requestId 를 안 줬다" 로 보고 실패로 끝낸다. */
static String _ticket(const String &p_id) {
	return "{\"requestId\":\"" + p_id + "\"}";
}

static String _next_id() {
	static uint64_t n = 0;
	return "sk" + itos(++n);
}

GodotIap::GodotIap() {
	GodotIapImpl *impl = new GodotIapImpl();
	if (@available(iOS 15.0, *)) {
#ifdef DEBUG_ENABLED
		// 진단은 **디버그 빌드에서만** 파일로 남긴다 (아래 `logging` 주석 참고).
		// 여기는 `.debug.xcframework` 로만 들어가므로 엔진이 알아서 갈라 준다.
		[GodotStoreKitBridge setLogging:YES];
#endif
		impl->bridge = [[GodotStoreKitBridge alloc] init];
		impl->relay = [[GodotIapRelay alloc] init];
		impl->relay.owner = this;
		impl->bridge.delegate = impl->relay;
	}
	bridge = impl;
}

GodotIap::~GodotIap() {
	GodotIapImpl *impl = (GodotIapImpl *)bridge;
	if (impl) {
		if (impl->relay) impl->relay.owner = nullptr;
		delete impl;
	}
}

#define IMPL GodotIapImpl *impl = (GodotIapImpl *)bridge; \
	if (!impl || !impl->bridge) return _ticket("unavailable");

String GodotIap::initConnection() {
	IMPL
	String id = _next_id();
	if (@available(iOS 15.0, *)) {
		[impl->bridge initConnection:[NSString stringWithUTF8String:id.utf8().get_data()]];
	}
	return _ticket(id);
}

String GodotIap::endConnection() {
	IMPL
	String id = _next_id();
	if (@available(iOS 15.0, *)) {
		[impl->bridge endConnection:[NSString stringWithUTF8String:id.utf8().get_data()]];
	}
	return _ticket(id);
}

String GodotIap::fetchProducts(const String &p_request_json) {
	IMPL
	String id = _next_id();
	/* 요청에서 상품 id 만 꺼낸다. 나머지 칸(type 등)은 StoreKit 2 에 해당이 없다. */
	Dictionary req = _parse(p_request_json);
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	Array skus = req.get("skus", Array());
	for (int i = 0; i < skus.size(); i++) {
		[ids addObject:[NSString stringWithUTF8String:String(skus[i]).utf8().get_data()]];
	}
	if (@available(iOS 15.0, *)) {
		[impl->bridge fetchProducts:[NSString stringWithUTF8String:id.utf8().get_data()] ids:ids];
	}
	return _ticket(id);
}

String GodotIap::requestPurchaseWithPayload(const String &p_payload_json) {
	IMPL
	/* 결과를 여기서 안 돌려준다 — 산 것은 purchase_updated, 취소·실패는 purchase_error 로 간다. */
	Dictionary payload = _parse(p_payload_json);
	Dictionary request = payload.get("requestPurchase", payload.get("requestSubscription", Dictionary()));
	Dictionary apple = request.get("apple", Dictionary());
	String sku = apple.get("sku", "");
	if (sku.is_empty()) {
		return "{\"success\":false,\"code\":\"developer-error\"}";
	}
	if (@available(iOS 15.0, *)) {
		[impl->bridge requestPurchase:[NSString stringWithUTF8String:sku.utf8().get_data()]];
	}
	return "{\"success\":true}";
}

String GodotIap::finishTransaction(const String &p_args_json) {
	IMPL
	String id = _next_id();
	Dictionary args = _parse(p_args_json);
	Dictionary purchase = args.get("purchase", Dictionary());
	/* **`isConsumable` 은 일부러 안 쓴다.** 우리가 파는 것은 전부 영구 소유다.
	 * StoreKit 2 에는 소비 개념이 없어 원래 안전하지만, 인자를 받는 것은 계약 때문이다. */
	String tx = purchase.get("transactionId", purchase.get("id", ""));
	if (@available(iOS 15.0, *)) {
		[impl->bridge finishTransaction:[NSString stringWithUTF8String:id.utf8().get_data()]
						 transactionId:[NSString stringWithUTF8String:tx.utf8().get_data()]];
	}
	return _ticket(id);
}

String GodotIap::getAvailablePurchases(const String &p_options_json) {
	IMPL
	String id = _next_id();
	if (@available(iOS 15.0, *)) {
		[impl->bridge getAvailablePurchases:[NSString stringWithUTF8String:id.utf8().get_data()]];
	}
	return _ticket(id);
}

String GodotIap::restorePurchases() {
	IMPL
	String id = _next_id();
	if (@available(iOS 15.0, *)) {
		[impl->bridge restorePurchases:[NSString stringWithUTF8String:id.utf8().get_data()]];
	}
	return _ticket(id);
}

/* **비동기 결과는 전부 `products_fetched` 로 나간다.** 이름이 어울리지 않지만
 * 그게 계약이다 — `godot_iap.gd::_on_products_fetched` 가 method·requestId 로
 * 어느 호출의 답인지 맞춘다. 다른 신호로 보내면 영영 안 깨어난다. */
/* **`call_deferred` 로 보낸다.** Swift 의 `Task` 는 백그라운드에서 도는데
 * Godot 은 거기서 신호를 쏘면 안 된다 — 받는 쪽이 GDScript 라 그 자리에서
 * 스크립트를 실행하게 되고, 그건 스레드 안전하지 않다.
 * 가격 조회가 그냥 됐던 것은 운이 좋았던 것이지 괜찮았던 것이 아니다. */
void GodotIap::_deliver_async(const String &p_json) {
	call_deferred(SNAME("emit_signal"), "products_fetched", _parse(p_json));
}

void GodotIap::_deliver_purchase(const String &p_json) {
	call_deferred(SNAME("emit_signal"), "purchase_updated", _parse(p_json));
}

void GodotIap::_deliver_error(const String &p_json) {
	call_deferred(SNAME("emit_signal"), "purchase_error", _parse(p_json));
}

void GodotIap::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initConnection"), &GodotIap::initConnection);
	ClassDB::bind_method(D_METHOD("endConnection"), &GodotIap::endConnection);
	ClassDB::bind_method(D_METHOD("fetchProducts", "request_json"), &GodotIap::fetchProducts);
	ClassDB::bind_method(D_METHOD("requestPurchaseWithPayload", "payload_json"), &GodotIap::requestPurchaseWithPayload);
	ClassDB::bind_method(D_METHOD("finishTransaction", "args_json"), &GodotIap::finishTransaction);
	ClassDB::bind_method(D_METHOD("getAvailablePurchases", "options_json"), &GodotIap::getAvailablePurchases);
	ClassDB::bind_method(D_METHOD("restorePurchases"), &GodotIap::restorePurchases);

	/* 일곱 개를 다 둔다. 오토로드가 `has_signal()` 로 하나씩 확인하고 잇는다 —
	 * 빠진 것은 조용히 안 이어지고, 그러면 그 기능만 사라진다. */
	ADD_SIGNAL(MethodInfo("purchase_updated", PropertyInfo(Variant::DICTIONARY, "purchase")));
	ADD_SIGNAL(MethodInfo("purchase_error", PropertyInfo(Variant::DICTIONARY, "error")));
	ADD_SIGNAL(MethodInfo("products_fetched", PropertyInfo(Variant::DICTIONARY, "result")));
	ADD_SIGNAL(MethodInfo("connected"));
	ADD_SIGNAL(MethodInfo("disconnected"));
	ADD_SIGNAL(MethodInfo("promoted_product", PropertyInfo(Variant::STRING, "product_id")));
	ADD_SIGNAL(MethodInfo("subscription_billing_issue", PropertyInfo(Variant::DICTIONARY, "purchase")));
}
