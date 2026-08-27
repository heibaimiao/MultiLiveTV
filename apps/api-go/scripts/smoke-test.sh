#!/usr/bin/env bash
# 对照测试：Go API vs 预期行为
set -euo pipefail
BASE="${1:-http://localhost:8080}"

echo "== health =="
curl -sf "$BASE/health" | grep -q '"status":"ok"' && echo OK

echo "== sources =="
COUNT=$(curl -sf "$BASE/api/v1/sources" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['sources']))")
echo "sources: $COUNT"
test "$COUNT" -gt 0

echo "== search 鲨笼绝境 (expect merged total=1) =="
RESULT=$(curl -sf --max-time 120 "$BASE/api/v1/vod/search?wd=%E9%B2%A8%E7%AC%BC%E7%BB%9D%E5%A2%83")
TOTAL=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['total'])")
echo "total: $TOTAL"
test "$TOTAL" -eq 1

echo "== detail =="
VOD_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['list'][0]['vod_id'])")
SOURCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['list'][0].get('primarySourceId') or d['list'][0]['variants'][0]['sourceId'])")
DETAIL=$(curl -sf --max-time 60 "$BASE/api/v1/vod/detail?sourceId=$SOURCE_ID&ids=$VOD_ID")
PS=$(echo "$DETAIL" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('playSources',[])))")
echo "playSources: $PS"
test "$PS" -gt 0

echo "ALL TESTS PASSED"
