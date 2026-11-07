#!/bin/bash
# smoke.sh — prove both scripts do what their headers claim, without a network.
#
# Runs on Linux and macOS.  Everything happens in a temp dir: no ssh, no curl,
# no writes outside it.  Exit 0 = every assertion held.
set -uo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-kit.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

fails=0
ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
want() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

# ---------- patrol.sh -------------------------------------------------------
printf 'INFO boot\nERROR first\n' > "$T/app.log"
printf 'x' > "$T/heartbeat"

cat > "$T/patrol.conf" <<EOF
NAME="smoke"
STATE_DIR="$T/state"
CHECKS=(
  "cmd|true-cmd|5|true"
  "lognew|errors|$T/app.log|ERROR|FATAL"
  "state|hb|$T/heartbeat|600"
)
EOF

# run 1: the first lognew run only arms the byte offset
out=$("$HERE/bin/patrol.sh" "$T/patrol.conf"); rc=$?
want "run1 exits 0" "$rc" "0"
want "run1 arms the log baseline" "$(printf '%s' "$out" | grep -c 'errors=baseline')" "1"
want "run1 reports a fresh heartbeat" "$(printf '%s' "$out" | grep -c 'hb=')" "1"
want "run1 prints a single OK line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

# run 2: nothing appended -> no signal
"$HERE/bin/patrol.sh" "$T/patrol.conf" >/dev/null; rc=$?
want "run2 (no new line) exits 0" "$rc" "0"

# run 3: one new ERROR -> SIGNAL, exit 2, and the phrase names the count
printf 'ERROR second\n' >> "$T/app.log"
out=$("$HERE/bin/patrol.sh" "$T/patrol.conf"); rc=$?
want "run3 (new ERROR) exits 2" "$rc" "2"
want "run3 names the hit count" "$(printf '%s' "$out" | grep -c 'ERROR\|1hit')" "1"

# run 4: a stale heartbeat must raise, not be counted
touch -t 202001010000 "$T/heartbeat"
out=$("$HERE/bin/patrol.sh" "$T/patrol.conf"); rc=$?
want "run4 (stale heartbeat) exits 2" "$rc" "2"
want "run4 says stale" "$(printf '%s' "$out" | grep -c 'hb=stale')" "1"

# run 5: a missing file is a signal, not a silent pass
rm -f "$T/heartbeat"
out=$("$HERE/bin/patrol.sh" "$T/patrol.conf")
want "run5 (missing file) says absent" "$(printf '%s' "$out" | grep -c 'hb=absent')" "1"

# run 6: a rotated log resets the baseline instead of replaying history
printf 'x' > "$T/heartbeat"                              # restore the file run5 removed
: > "$T/app.log"
printf 'ERROR after rotation\n' > "$T/app.log"
"$HERE/bin/patrol.sh" "$T/patrol.conf" >/dev/null      # offset > size -> rotated
out=$("$HERE/bin/patrol.sh" "$T/patrol.conf"); rc=$?
want "run6 does not replay a truncated log" "$rc" "0"

# run 7: usage error is exit 1, not 2
"$HERE/bin/patrol.sh" "$T/nope.conf" >/dev/null 2>&1
want "missing config exits 1" "$?" "1"

# ---------- review-gate.sh --------------------------------------------------
mkdir -p "$T/tree/src"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'x%s\n' "$i" > "$T/tree/src/f$i.go"; done
rg() { ROOT="$T/tree" OUT="$T/tree/.review-gate" MIN_FILES=10 "$HERE/bin/review-gate.sh" "$@"; }

h1=$(rg hash)
want "hash is 64 hex chars" "${#h1}" "64"

rg require >/dev/null 2>&1
want "unsigned tree is refused" "$?" "1"

rg sign code PASS "smoke" >/dev/null
rg sign security PASS "smoke" >/dev/null
rg require >/dev/null 2>&1
want "both signatures let it through" "$?" "0"

printf 'y\n' >> "$T/tree/src/f3.go"
rg require >/dev/null 2>&1
want "editing one line invalidates both" "$?" "1"

h2=$(rg hash)
[ "$h1" != "$h2" ] && ok "the tree hash moved with the edit" || bad "tree hash did not move"

rg sign code FAIL "smoke" >/dev/null
rg require >/dev/null 2>&1
want "a FAIL verdict blocks the gate" "$?" "1"

S="$T/small"; mkdir -p "$S/src"; printf 'a\n' > "$S/src/a.go"
ROOT="$S" OUT="$S/.rg" "$HERE/bin/review-gate.sh" hash >/dev/null 2>&1
want "a tree below MIN_FILES cannot be signed" "$?" "1"

# ---------- verdict ---------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  echo "STATUS: ok -- both scripts behave as documented"
  exit 0
fi
echo "STATUS: FAILED -- $fails assertion(s)"
exit 1
