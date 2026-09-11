/*  Godot 클래스 `GodotIap` — StoreKit 2 (iOS 15+).
 *
 *  **이름을 바꾸면 안 된다.** `addons/godot-iap/godot_iap.gd` 가
 *  `ClassDB.instantiate("GodotIap")` 로 잡는다. 그 GDScript 2,052줄과
 *  안드로이드 경로를 그대로 두고 **iOS 네이티브만** 갈아 끼우는 것이 이 플러그인의 목적이다.
 *
 *  원래 쓰던 OpenIAP 은 SwiftGodot 위에 서 있고, SwiftGodot 이 Swift 파라미터 팩을 써서
 *  **iOS 17 런타임**을 요구한다. 그 프레임워크가 임베드되면 iOS 15·16 기기에서
 *  dyld 가 로드를 거부해 켜자마자 죽는다.
 */
#ifndef GODOT_IAP_H
#define GODOT_IAP_H

#include "core/object/class_db.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/string/ustring.h"

class GodotIap : public RefCounted {
	GDCLASS(GodotIap, RefCounted);

	static void _bind_methods();

	void *bridge = nullptr;          // GodotStoreKitBridge (Swift)

public:
	/* 아래 이름들은 `godot_iap.gd` 가 `call()`/`callv()` 로 부르는 그대로다.
	 * 카멜케이스인 것은 그쪽 계약이라 Godot 관례를 따르지 않는다. */
	String initConnection();
	String endConnection();
	String fetchProducts(const String &p_request_json);
	String requestPurchaseWithPayload(const String &p_payload_json);
	String finishTransaction(const String &p_args_json);
	String getAvailablePurchases(const String &p_options_json);
	String restorePurchases();

	/* Swift 쪽에서 올라온다 */
	void _deliver_async(const String &p_json);
	void _deliver_purchase(const String &p_json);
	void _deliver_error(const String &p_json);

	GodotIap();
	~GodotIap();
};

#endif // GODOT_IAP_H
