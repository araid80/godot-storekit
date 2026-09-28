/* 등록.
 *
 * **ClassDB 클래스로 등록한다** — `godot_iap.gd` 가
 * `ClassDB.instantiate("GodotIap")` 로 잡기 때문이다 (싱글턴이 아니다).
 *
 * 싱글턴은 두지 않는다. `GodotIap` 은 `RefCounted` 라 `memnew` 이 `Ref<>` 를 돌려주고,
 * `Engine::add_singleton` 은 날 포인터를 받아 서로 안 맞는다.
 * 어차피 오토로드가 쓰는 길은 ClassDB 하나뿐이다. */
#include "godot_iap.h"
#include "godot_review.h"

#include "core/object/class_db.h"

void register_godotstorekit_types() {
	ClassDB::register_class<GodotIap>();
	/* 별점 창. **같은 플러그인에 둔다** — `SKStoreReviewController` 도 StoreKit 이고,
	 * 프레임워크(`StoreKit.framework`)가 이미 링크돼 있어 더 붙일 것이 없다. */
	ClassDB::register_class<GodotReview>();
}

void unregister_godotstorekit_types() {
}
