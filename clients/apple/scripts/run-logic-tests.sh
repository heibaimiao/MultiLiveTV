#!/bin/sh
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
conflicting = {
    "NSAllowsArbitraryLoadsForMedia",
    "NSAllowsArbitraryLoadsInWebContent",
    "NSAllowsLocalNetworking",
}
files = [
    "MultiLiveTV/Info-tvOS.plist",
    "MultiLiveTV/Info-iOS.plist",
    "MultiLiveTVTopShelf/Info.plist",
]
for name in files:
    ats = plistlib.loads((root / name).read_bytes()).get("NSAppTransportSecurity") or {}
    if ats.get("NSAllowsArbitraryLoads") is not True:
        raise SystemExit(f"{name}: NSAllowsArbitraryLoads must be true")
    extra = conflicting.intersection(ats)
    if extra:
        raise SystemExit(f"{name}: {sorted(extra)} would make NSAllowsArbitraryLoads ignored")
print("ATS plist check passed")
PY
OUT="$(mktemp -t multilivetv-logic-tests)"
swiftc -o "$OUT" \
  "$ROOT/MultiLiveTV/Models/Models.swift" \
  "$ROOT/MultiLiveTV/Services/VodDisplayFormatter.swift" \
  "$ROOT/MultiLiveTV/Services/HomeFeed.swift" \
  "$ROOT/MultiLiveTV/Services/HomeLaunch.swift" \
  "$ROOT/MultiLiveTV/Services/MacCMSModels.swift" \
  "$ROOT/MultiLiveTV/Services/SourceMovie.swift" \
  "$ROOT/MultiLiveTV/Services/SourceHealthStore.swift" \
  "$ROOT/MultiLiveTV/Services/SourceAdapter.swift" \
  "$ROOT/MultiLiveTV/Services/SourceStore.swift" \
  "$ROOT/MultiLiveTV/Services/NetworkConfig.swift" \
  "$ROOT/MultiLiveTV/Services/RemoteImageLoader.swift" \
  "$ROOT/MultiLiveTV/Services/TopShelf/AppDeepLink.swift" \
  "$ROOT/MultiLiveTV/Services/TopShelf/TopShelfSnapshot.swift" \
  "$ROOT/MultiLiveTV/Services/TopShelf/TopShelfStore.swift" \
  "$ROOT/MultiLiveTV/Services/PlaybackSupport.swift" \
  "$ROOT/MultiLiveTV/Services/VodPlaybackFailover.swift" \
  "$ROOT/MultiLiveTV/Services/PlayLineWeights.swift" \
  "$ROOT/MultiLiveTV/Services/PlayParser.swift" \
  "$ROOT/MultiLiveTV/Services/MacCMSClient.swift" \
  "$ROOT/MultiLiveTV/Services/VodMergeService.swift" \
  "$ROOT/MultiLiveTV/Services/CategoryListService.swift" \
  "$ROOT/MultiLiveTV/Services/UnifiedCategories.swift" \
  "$ROOT/MultiLiveTV/Services/CategoryTree.swift" \
  "$ROOT/MultiLiveTV/Services/CategoryMatch.swift" \
  "$ROOT/MultiLiveTV/Services/Live/LiveModels.swift" \
  "$ROOT/MultiLiveTV/Services/Live/HLSPlaylistProbe.swift" \
  "$ROOT/MultiLiveTV/Services/Live/M3UPlaylistParser.swift" \
  "$ROOT/MultiLiveTV/Services/Live/LiveStore.swift" \
  "$ROOT/scripts/verify-client-logic.swift"
exec "$OUT"
