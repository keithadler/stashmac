#!/bin/bash
# Throughput and memory on a synthetic folder: N files of 4 MB (default 500 → 2 GB), backed up to a
# local folder, then verified and restored. Not part of CI; run it by hand.
#   ./tests/perf.sh [files] ["path/to/Stash for Mac.app"]
set -uo pipefail
cd "$(dirname "$0")/.."
N="${1:-500}"; APP="${2:-build/Stash for Mac.app}"; B="$APP/Contents/MacOS/StashMac"
[ -x "$B" ] || { echo "no app at $APP"; exit 2; }
export STASHMAC_TEST; STASHMAC_TEST=$(mktemp -d); SRC=$(mktemp -d); DEST=$(mktemp -d); OUT=$(mktemp -d)
trap 'defaults delete com.keithadler.stashmac.test >/dev/null 2>&1; rm -rf "$STASHMAC_TEST" "$SRC" "$DEST" "$OUT"' EXIT
echo "generating $N x 4 MB files…"
for i in $(seq 1 "$N"); do head -c 4194304 /dev/urandom > "$SRC/f$i.bin"; done
"$B" key new >/dev/null; "$B" add "$SRC" >/dev/null; "$B" dest "$DEST" >/dev/null
echo "== first backup (all new)"
/usr/bin/time -l "$B" backup 2>&1 | grep -E "files,|real|maximum resident" | sed 's/^ *//'
echo "== second backup (nothing new)"
/usr/bin/time -l "$B" backup 2>&1 | grep -E "files,|real|maximum resident" | sed 's/^ *//'
echo "== verify"
/usr/bin/time -l "$B" verify 2>&1 | grep -E "chunks|real|maximum resident" | sed 's/^ *//'
echo "== restore"
/usr/bin/time -l "$B" restore latest "$OUT" 2>&1 | grep -E "restored|real|maximum resident" | sed 's/^ *//'
