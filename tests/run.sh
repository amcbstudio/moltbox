#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/molt"
BASE="https://www.moltbook.com/api/v1"

pass() {
  printf '%s\n' "ok: $1"
}

fail() {
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

run_cmd() {
  OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/molt-test-out.XXXXXX")
  ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/molt-test-err.XXXXXX")
  set +e
  "$@" >"$OUT_FILE" 2>"$ERR_FILE"
  RC=$?
  set -e
  OUT=$(cat "$OUT_FILE")
  ERR=$(cat "$ERR_FILE")
  rm -f "$OUT_FILE" "$ERR_FILE"
}

# Test: missing API key exits 2
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  MOCK_CURL_FIXTURE="$ROOT/fixtures/status.json" \
  "$BIN" status
[ "$RC" -eq 2 ] || fail "missing API key should exit 2"
echo "$OUT" | jq -e '.type=="error" and .op=="status"' >/dev/null || fail "missing API key should output error JSON"
pass "missing API key"

# Test: publish agentbox missing API key exits 2
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  "$BIN" publish agentbox --memory-dir "$ROOT/tests/fixtures/agentbox"
[ "$RC" -eq 2 ] || fail "publish agentbox missing API key should exit 2"
echo "$OUT" | jq -e '.type=="error" and .op=="publish_agentbox"' >/dev/null || fail "publish agentbox missing API key should output error JSON"
pass "publish agentbox missing API key"

# Test: publish agentbox missing MEMORY.md exits 2
MISSING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/molt-missing.XXXXXX")
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  "$BIN" publish agentbox --memory-dir "$MISSING_DIR"
[ "$RC" -eq 2 ] || fail "publish agentbox missing MEMORY.md should exit 2"
echo "$OUT" | jq -e '.type=="error" and .op=="publish_agentbox"' >/dev/null || fail "publish agentbox missing MEMORY.md should output error JSON"
pass "publish agentbox missing MEMORY.md"
rm -rf "$MISSING_DIR"

# Test: publish agentbox comment mode without post-id exits 2
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  "$BIN" publish agentbox --mode comment --memory-dir "$ROOT/tests/fixtures/agentbox"
[ "$RC" -eq 2 ] || fail "publish agentbox comment mode missing post-id should exit 2"
echo "$OUT" | jq -e '.type=="error" and .op=="publish_agentbox"' >/dev/null || fail "publish agentbox comment mode should output error JSON"
pass "publish agentbox comment mode missing post-id"

# Test: correct URL and no redirects
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  MOLTBOOK_API_KEY="testkey" \
  MOCK_CURL_FIXTURE="$ROOT/fixtures/status.json" \
  MOCK_CURL_STATUS=200 \
  MOCK_CURL_EXPECT_URL="$BASE/agents/status" \
  MOCK_CURL_FORBID_L=1 \
  "$BIN" status
[ "$RC" -eq 0 ] || fail "status should exit 0"
echo "$OUT" | jq -e '.status=="ok"' >/dev/null || fail "status output mismatch"
pass "status url + no redirect"

# Test: publish agentbox jsonl events include op
EVENTS_FILE=$(mktemp "${TMPDIR:-/tmp}/molt-events.XXXXXX")
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  MOLTBOOK_API_KEY="testkey" \
  MOCK_CURL_FIXTURE="$ROOT/fixtures/status.json" \
  MOCK_CURL_STATUS=200 \
  MOCK_CURL_EXPECT_URL="$BASE/posts" \
  "$BIN" publish agentbox --memory-dir "$ROOT/tests/fixtures/agentbox" --jsonl-events "$EVENTS_FILE"
[ "$RC" -eq 0 ] || fail "publish agentbox should exit 0"
[ -s "$EVENTS_FILE" ] || fail "publish agentbox events file should be written"
EXPECTED_BYTES=$(wc -c < "$ROOT/fixtures/status.json" | awk '{print $1}')
EXPECTED_SHA=$(hash_file "$ROOT/fixtures/status.json")
LINE=$(head -n 1 "$EVENTS_FILE")
printf '%s' "$LINE" | jq -e \
  --argjson bytes "$EXPECTED_BYTES" \
  --arg sha "$EXPECTED_SHA" \
  '.op=="publish_agentbox" and .ok==true and .submolt=="general" and .bytes==$bytes and .sha256==$sha' >/dev/null || fail "publish agentbox event content mismatch"
pass "publish agentbox jsonl events"
rm -f "$EVENTS_FILE"

# Test: jsonl events include sha256 and bytes
EVENTS_FILE=$(mktemp "${TMPDIR:-/tmp}/molt-events.XXXXXX")
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  MOLTBOOK_API_KEY="testkey" \
  MOCK_CURL_FIXTURE="$ROOT/fixtures/feed.json" \
  MOCK_CURL_STATUS=200 \
  "$BIN" feed --sort new --limit 2 --jsonl-events "$EVENTS_FILE"
[ "$RC" -eq 0 ] || fail "feed should exit 0"
[ -s "$EVENTS_FILE" ] || fail "events file should be written"
EXPECTED_BYTES=$(wc -c < "$ROOT/fixtures/feed.json" | awk '{print $1}')
EXPECTED_SHA=$(hash_file "$ROOT/fixtures/feed.json")
LINE=$(head -n 1 "$EVENTS_FILE")
printf '%s' "$LINE" | jq -e \
  --argjson bytes "$EXPECTED_BYTES" \
  --arg sha "$EXPECTED_SHA" \
  '.op=="feed" and .ok==true and .bytes==$bytes and .sha256==$sha' >/dev/null || fail "event content mismatch"
pass "jsonl events"
rm -f "$EVENTS_FILE"

# Test: 429 surfaces retry hints
run_cmd env PATH="$ROOT/tests/bin:$PATH" \
  MOLTBOOK_API_KEY="testkey" \
  MOCK_CURL_FIXTURE="$ROOT/fixtures/429.json" \
  MOCK_CURL_STATUS=429 \
  "$BIN" feed
[ "$RC" -eq 1 ] || fail "429 should exit 1"
echo "$OUT" | jq -e '.type=="error" and .op=="feed" and .retry_after_seconds==30' >/dev/null || fail "429 retry hint missing"
pass "429 retry hints"

printf '%s\n' "All tests passed."
