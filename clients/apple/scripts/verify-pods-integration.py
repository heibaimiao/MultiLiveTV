#!/usr/bin/env python3
"""Fail if VLCKit cannot be linked without CocoaPods Copy XCFrameworks.

XcodeGen's default xcode16_0 format and CocoaPods 1.17 both skip a native
target dependency on Pods-MultiLiveTV-*. The app target must copy the
xcframework slice itself, and FRAMEWORK_SEARCH_PATHS must include that slice.
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBX = ROOT / "MultiLiveTV.xcodeproj" / "project.pbxproj"
WORKSPACE = ROOT / "MultiLiveTV.xcworkspace" / "contents.xcworkspacedata"
TVOS_XCCONFIG = (
    ROOT
    / "Pods"
    / "Target Support Files"
    / "Pods-MultiLiveTV-tvOS"
    / "Pods-MultiLiveTV-tvOS.debug.xcconfig"
)
IOS_XCCONFIG = (
    ROOT
    / "Pods"
    / "Target Support Files"
    / "Pods-MultiLiveTV-iOS"
    / "Pods-MultiLiveTV-iOS.debug.xcconfig"
)


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not WORKSPACE.is_file():
        fail("MultiLiveTV.xcworkspace missing; run pod install and open the workspace")
    if "Pods/Pods.xcodeproj" not in WORKSPACE.read_text():
        fail("workspace does not include Pods/Pods.xcodeproj")

    if not PBX.is_file():
        fail("MultiLiveTV.xcodeproj/project.pbxproj missing")
    pbx = PBX.read_text()

    if "objectVersion = 77" in pbx or "preferredProjectObjectVersion = 77" in pbx:
        fail(
            "project format is Xcode 16 objectVersion 77; set projectFormat: xcode15_0"
        )

    if "Copy VLCKit XCFramework slice" not in pbx:
        fail("app targets must run Copy VLCKit XCFramework slice before linking")

    # CocoaPods 1.17 links this dummy umbrella but never builds it first.
    if "Pods_MultiLiveTV_tvOS.framework in Frameworks" in pbx:
        fail("tvOS app must not link Pods_MultiLiveTV_tvOS; TVVLCKit is already in OTHER_LDFLAGS")
    if "Pods_MultiLiveTV_iOS.framework in Frameworks" in pbx:
        fail("iOS app must not link Pods_MultiLiveTV_iOS; MobileVLCKit is already in OTHER_LDFLAGS")

    if not TVOS_XCCONFIG.is_file() or not IOS_XCCONFIG.is_file():
        fail("Pods xcconfig missing; run pod install")

    tvos = TVOS_XCCONFIG.read_text()
    ios = IOS_XCCONFIG.read_text()
    if "tvos-arm64_x86_64-simulator" not in tvos:
        fail("tvOS xcconfig must search TVVLCKit.xcframework simulator slice")
    if "ios-arm64_i386_x86_64-simulator" not in ios:
        fail("iOS xcconfig must search MobileVLCKit.xcframework simulator slice")

    print("CocoaPods VLCKit integration check passed")


if __name__ == "__main__":
    main()
