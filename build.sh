#!/bin/bash
# iOS 플러그인을 다시 빌드한다.
#
#   ./build.sh [godot-ios-plugins 경로]
#
# **Swift 를 먼저 굽고 ObjC++ 와 합친다.** StoreKit 2 는 Swift 전용 API 라
# 브리지가 Swift 여야 하는데, Godot iOS 플러그인은 정적 라이브러리 하나만 받는다.
# 그래서 `libtool` 로 두 아카이브를 한 덩이로 만든다.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS="${1:-$HOME/Documents/works/godot-ios-plugins}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
# **엔진 태그와 같아야 한다.** 하네스의 godot/ 가 그 버전이어야 헤더가 맞는다.
TARGET="arm64-apple-ios15.0"     # StoreKit 2 의 바닥이 15.0 이다
WORK="$(mktemp -d)"

[ -d "$HARNESS/plugins" ] || { echo "[!!] 하네스가 없다: $HARNESS"; exit 1; }

echo "[1/4] Swift 브리지"
for kind in release debug; do
  EXTRA="" ; [ "$kind" = debug ] && EXTRA="-Onone -g"
  swiftc -emit-library -static -emit-objc-header \
    -emit-objc-header-path "$WORK/GodotStoreKit-Swift.h" \
    -module-name GodotStoreKit -target "$TARGET" -sdk "$SDK" $EXTRA \
    -o "$WORK/swift-$kind.a" "$HERE/native/ios/StoreKitBridge.swift"
done

echo "[2/4] ObjC++ 플러그인"
mkdir -p "$HARNESS/plugins/godotstorekit"
cp "$HERE/native/ios/"*.mm "$HERE/native/ios/"*.h "$HARNESS/plugins/godotstorekit/"
cp "$WORK/GodotStoreKit-Swift.h" "$HARNESS/plugins/godotstorekit/"
# 하네스의 SConstruct 에 플러그인 이름이 등록돼 있어야 한다
grep -q "'godotstorekit'" "$HARNESS/SConstruct" || {
  echo "[!!] $HARNESS/SConstruct 의 plugin 목록에 'godotstorekit' 를 넣을 것"; exit 1; }
# **먼저 지운다.** scons 가 재빌드를 건너뛰어 **옛 라이브러리가 그대로 합쳐진 적이 있다** —
# 릴리스만 이틀 전 것이어서 디버그 전용 코드가 갈렸는지 확인하다 한참 헤맸다.
# 산출물이 없으면 건너뛸 수가 없다.
rm -f "$HARNESS"/bin/libgodotstorekit.arm64-ios.*.a
( cd "$HARNESS" && for kind in release debug; do
    scons platform=ios target=$kind arch=arm64 version=4.0 plugin=godotstorekit -j8 >/dev/null
    [ -f "$HARNESS/bin/libgodotstorekit.arm64-ios.$kind.a" ] || {
      echo "[!!] $kind 빌드 결과가 없다"; exit 1; }
  done )

echo "[3/4] 합치기"
for kind in release debug; do
  libtool -static -o "$WORK/merged-$kind.a" \
    "$HARNESS/bin/libgodotstorekit.arm64-ios.$kind.a" "$WORK/swift-$kind.a" 2>/dev/null
  # **디버그 정보를 떼어낸다.** 안 떼면 DWARF 에 **빌드한 기계의 절대 경로**가
  # 그대로 박힌다 (`/Users/<이름>/Documents/...`) — 공개 저장소에 올라가는 파일이다.
  # 지우는 것은 디버그 심볼뿐이라 링크에 필요한 전역 심볼은 남는다
  # (실측: /Users 7 → 0, 전역 심볼 45개 그대로, 2.2MB → 427KB).
  #
  # **원천(컴파일 플래그)에서 못 막는다** — ObjC++ 쪽은 하네스의 SConstruct 가
  # 컴파일하는데 그건 우리 저장소가 아니고 임의 CCFLAGS 를 안 받는다.
  strip -S "$WORK/merged-$kind.a"
  # **남으면 실패시킨다.** 조용히 새어 나가면 공개된 뒤에야 알게 된다.
  if strings -a "$WORK/merged-$kind.a" | grep -q '/Users/'; then
    echo "[!!] $kind 아카이브에 빌드 경로가 남았다:"
    strings -a "$WORK/merged-$kind.a" | grep '/Users/' | sort -u | head
    exit 1
  fi
done

echo "[4/4] xcframework"
# **디버그·릴리스 둘 다 있어야 한다** — 엔진이 둘 다 찾는다.
for kind in release debug; do
  rm -rf "$HERE/ios/godotstorekit.$kind.xcframework"
  xcodebuild -create-xcframework -library "$WORK/merged-$kind.a" \
    -output "$HERE/ios/godotstorekit.$kind.xcframework" >/dev/null
done
rm -rf "$WORK"
echo "[OK] ios/godotstorekit.{debug,release}.xcframework"
