#!/bin/bash
# End-to-end through the command line, with the key in a temp file and isolated defaults
# (STASHMAC_TEST), never touching the Keychain or a real backup.
#   ./tests/integration.sh ["path/to/Stash for Mac.app"]     default: build/Stash for Mac.app
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Stash for Mac.app}"; B="$APP/Contents/MacOS/StashMac"
[ -x "$B" ] || { echo "no app at $APP; run ./build-app.sh first"; exit 2; }
export STASHMAC_TEST; STASHMAC_TEST=$(mktemp -d); SRC=$(mktemp -d); DEST=$(mktemp -d); DEST2=$(mktemp -d); OUT=$(mktemp -d)
cleanup() { defaults delete com.keithadler.stashmac.test >/dev/null 2>&1; rm -rf "$STASHMAC_TEST" "$SRC" "$DEST" "$DEST2" "$OUT"; }
trap cleanup EXIT
fail=0; check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

mkdir -p "$SRC/photos" "$SRC/node_modules/x"; echo "hello" > "$SRC/notes.txt"; head -c 4500000 /dev/urandom > "$SRC/photos/big.bin"
cp "$SRC/photos/big.bin" "$SRC/photos/copy.bin"; : > "$SRC/empty.txt"; echo "ignored" > "$SRC/node_modules/x/i.js"

check "key new"                     '"$B" key new --json | grep -q fingerprint'
check "key new refuses a second"    '! "$B" key new >/dev/null 2>&1'
WORDS=$("$B" key show --json | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin)['words']))")
check "24 words"                    '[ $(echo "$WORDS" | wc -w) -eq 24 ]'
check "card pdf"                    '"$B" key card "$OUT/card.pdf" >/dev/null && head -c 5 "$OUT/card.pdf" | grep -q "%PDF"'
check "add and dest"                '"$B" add "$SRC" >/dev/null && "$B" dest "$DEST" >/dev/null && "$B" dest "$DEST2" >/dev/null'
check "status exits 0 when ready"   '"$B" status --json >/dev/null'
check "backup"                      '"$B" backup --json | grep -q "\"new_chunks\" : 4"'
check "two destinations written"    '[ -d "$DEST/Stash for Mac" ] && [ -d "$DEST2/Stash for Mac" ]'
check "chunks are ciphertext"       '! grep -rl hello "$DEST" >/dev/null'
check "second backup uploads nothing" '"$B" backup --json | grep -q "\"new_chunks\" : 0"'
check "snapshots listed"            '"$B" snapshots --json | grep -c "\"snapshot\"" | grep -q 4'
check "verify ok"                   '"$B" verify --json | grep -q "\"sample_ok\" : true"'
check "restore identical"           '"$B" restore latest "$OUT/r" >/dev/null && diff -r -x node_modules "$SRC" "$OUT/r/$(basename "$SRC")" >/dev/null'
check "restore subtree"             '"$B" restore latest "$OUT/s" --only photos >/dev/null && [ -f "$OUT/s/$(basename "$SRC")/photos/big.bin" ] && [ ! -f "$OUT/s/$(basename "$SRC")/notes.txt" ]'
c=$(find "$DEST/Stash for Mac" -path "*/chunks/*" -type f | head -1); printf "x" >> "$c"
VOUT=$("$B" verify --json 2>/dev/null); VEXIT=$?
check "tampered chunk reported"     '[ "$VEXIT" = 2 ] && echo "$VOUT" | python3 -c "import json,sys; rs=json.load(sys.stdin)[\"results\"]; sys.exit(0 if any(r.get(\"bad\") for r in rs) else 1)"'
check "key forget then restore words" '"$B" key forget >/dev/null && "$B" key restore "$WORDS" >/dev/null && "$B" snapshots --json | grep -q snapshot'
check "wrong word rejected"         '! "$B" key restore "$(echo "$WORDS" | sed "s/^[a-z]*/zoo/")" >/dev/null 2>&1'
check "selftest"                    '"$B" selftest --json | grep -q "\"failed\" : 0"'
[ $fail = 0 ] && echo "integration: all passed" || echo "integration: FAILURES"
exit $fail
