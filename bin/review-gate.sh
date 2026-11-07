#!/bin/bash
# review-gate.sh — refuse to deploy an unreviewed tree.
#
#   review-gate.sh hash                      # print the tree hash
#   review-gate.sh sign code PASS "why"      # record a code review
#   review-gate.sh sign security PASS "why"  # record a security review
#   review-gate.sh require                   # exit 1 unless BOTH signed this tree
#   review-gate.sh status
#
# The signature is bound to a hash of the source tree, so editing one line
# invalidates both reviews. Evidence lives in $OUT/<hash>.{code,security}.
set -uo pipefail

ROOT="${ROOT:-$(pwd)}"
OUT="${OUT:-$ROOT/.review-gate}"
PATHS="${PATHS:-src lib scripts deploy}"
EXTS="${EXTS:-go js py sh json sql mod sum}"
MIN_FILES="${MIN_FILES:-10}"

list_files() {
  local p
  for p in $PATHS; do
    [ -e "$ROOT/$p" ] || continue
    find "$ROOT/$p" -type f \
      \( -name '*.go' -o -name '*.js' -o -name '*.py' -o -name '*.sh' \
         -o -name '*.json' -o -name '*.sql' -o -name '*.mod' -o -name '*.sum' \) \
      -not -path '*/node_modules/*' -not -path '*/.git/*' \
      -not -path '*/bin/*' -not -path '*/__pycache__/*' \
      -not -name '*.bak*' -not -name '*.test.js' 2>/dev/null
  done | sort
}

hash_tree() {
  local n
  n=$(list_files | wc -l | tr -d ' ')
  # an empty or suspiciously small tree hashes to a constant; refuse to sign it
  [ "${n:-0}" -ge "$MIN_FILES" ] || { echo "review-gate: only $n files matched (MIN_FILES=$MIN_FILES)" >&2; return 1; }
  list_files | while read -r f; do
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f"; else sha256sum "$f"; fi
  done | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; } | cut -d' ' -f1
}

mkdir -p "$OUT"
H=$(hash_tree) || exit 1
[ -n "$H" ] || exit 1

case "${1:-require}" in
  hash) echo "$H" ;;
  status)
    echo "tree: $H"
    for k in code security; do
      f="$OUT/$H.$k"
      if [ -r "$f" ]; then printf '  %-8s %s\n' "$k" "$(head -1 "$f")"; else printf '  %-8s %s\n' "$k" "MISSING"; fi
    done ;;
  sign)
    kind="${2:-}"; verdict="${3:-}"; why="${4:-}"
    case "$kind" in code|security) ;; *) echo "sign <code|security> <PASS|FAIL> <why>" >&2; exit 1 ;; esac
    [ -n "$verdict" ] || { echo "verdict required" >&2; exit 1; }
    printf '%s %s %s hash=%s %s\n' "$verdict" "$(date -u +%FT%TZ)" "${REVIEWER:-$(whoami)}" "$H" "$why" > "$OUT/$H.$kind"
    echo "signed $kind=$verdict for $H" ;;
  require)
    missing=0
    for k in code security; do
      f="$OUT/$H.$k"
      if [ ! -r "$f" ] || ! head -1 "$f" | grep -q '^PASS'; then
        echo "review-gate: $k review missing or not PASS for tree $H" >&2; missing=1
      fi
    done
    exit $missing ;;
  *) echo "usage: review-gate.sh [hash|sign|require|status]" >&2; exit 1 ;;
esac
