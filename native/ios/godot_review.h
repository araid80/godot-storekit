/*  Godot 클래스 `GodotReview` — 별점 창 부탁 (SKStoreReviewController).
 *
 *  **자체 별점 창을 그리면 안 된다.** 애플이 제공된 API 를 쓰라고 못 박아 두었고
 *  ("we will disallow custom review prompts") 구글도 인앱 리뷰를 권한다.
 *
 *  **Swift 가 필요 없다.** `SKStoreReviewController` 는 ObjC API 라
 *  `StoreKitBridge.swift` 를 건드리지 않고 여기서 끝난다.
 *  (StoreKit 2 의 `AppStore.requestReview(in:)` 은 iOS 16+ · Swift 전용이라 안 쓴다 —
 *   우리 바닥은 15.0 이다.)
 *
 *  **띄웠는지는 알 수 없다.** 애플이 365일에 3번으로 묶어 두고 결과를 안 알려 준다.
 *  그래서 반환값이 없다 — 부르는 쪽은 "넘겼다" 까지만 안다.
 */
#ifndef GODOT_REVIEW_H
#define GODOT_REVIEW_H

#include "core/object/class_db.h"
#include "core/object/ref_counted.h"

class GodotReview : public RefCounted {
	GDCLASS(GodotReview, RefCounted);

	static void _bind_methods();

public:
	void request();
};

#endif // GODOT_REVIEW_H
