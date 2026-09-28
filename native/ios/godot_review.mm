#include "godot_review.h"

#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

/*  띄울 씬을 찾는다.
 *
 *  **`[[UIApplication sharedApplication] delegate].window` 를 쓰면 안 된다** —
 *  Godot 4.5+ 는 `UIWindowSceneDelegate` 라 그 자리가 nil 이다
 *  (Game Center 플러그인에서 겪은 것과 같은 함정). 연결된 씬에서 직접 찾는다.
 */
API_AVAILABLE(ios(13.0))
static UIWindowScene *_active_scene() {
	for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
		if (![s isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		if (s.activationState == UISceneActivationStateForegroundActive) {
			return (UIWindowScene *)s;
		}
	}
	/* 앞에 나와 있는 씬이 없으면 아무거나 하나. 창이 안 뜰 뿐 죽지는 않는다. */
	for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
		if ([s isKindOfClass:[UIWindowScene class]]) {
			return (UIWindowScene *)s;
		}
	}
	return nil;
}

void GodotReview::request() {
	/*  **메인 스레드에서 불러야 한다.** UI 를 띄우는 StoreKit 호출이라
	 *  백그라운드에서 부르면 창이 안 뜨거나 죽는다 (`purchase()` 와 같은 규칙). */
	dispatch_async(dispatch_get_main_queue(), ^{
		/*  **하네스의 배포 타깃은 12.0 이다** — 앱의 최소 버전(15.0)과 달라서
		 *  `@available` 로 감싸지 않으면 경고가 뜬다. 실기에서는 늘 참이다. */
		if (@available(iOS 14.0, *)) {
			UIWindowScene *scene = _active_scene();
			if (scene == nil) {
				NSLog(@"[Review] 씬을 못 찾았다 — 건너뛴다");
				return;
			}
			[SKStoreReviewController requestReviewInScene:scene];
			NSLog(@"[Review] 별점 창을 부탁했다 (띄울지는 스토어가 정한다)");
		}
	});
}

void GodotReview::_bind_methods() {
	ClassDB::bind_method(D_METHOD("request"), &GodotReview::request);
}
