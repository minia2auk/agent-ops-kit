#!/bin/bash
# patrol.sh — script-first patrol. Prints ONE judge line, then detail.
#
#   OK     <key numbers>     -> the model may repeat this line and stop
#   SIGNAL <reasons...>      -> the model should investigate
# Exits 0 on OK, 2 on SIGNAL, 1 on a config/usage error.
#
# Design rule (learned the hard way): a condition that is true most of the time
# is COUNTED in the OK line, never raised. Only a change of state raises.
# Otherwise every round is SIGNAL and the patrol is worthless.
#
# usage: patrol.sh <config-file>
set -uo pipefail

CONF="${1:-}"
[ -r "$CONF" ] || { echo "usage: patrol.sh <config>" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

: "${STATE_DIR:=.patrol-state}"
mkdir -p "$STATE_DIR"
NAME="${NAME:-patrol}"

signals=()
info=()

# ── checks ────────────────────────────────────────────────────────────────
# http <label> <url> [expected=200]
check_http() {
  local label="$1" url="$2" want="${3:-200}" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "${HTTP_TIMEOUT:-10}" "$url" 2>/dev/null)
  code=${code:-000}
  if [ "$code" != "$want" ]; then signals+=("$label=$code(want $want)"); else info+=("$label=$code"); fi
}

# cmd <label> <max-seconds> <command...>  — fails on non-zero or overshoot
check_cmd() {
  local label="$1" max="$2"; shift 2
  local t0 t1 rc
  t0=$(date +%s)
  "$@" >/dev/null 2>&1; rc=$?
  t1=$(date +%s)
  if [ "$rc" -ne 0 ]; then signals+=("$label=rc$rc"); return; fi
  if [ $((t1 - t0)) -gt "$max" ]; then signals+=("$label=slow$((t1 - t0))s"); return; fi
  info+=("$label=$((t1 - t0))s")
}

# lognew <label> <file> <grep-extended-pattern>
# Only lines appended SINCE the last run count. A rotated/truncated file resets
# the baseline instead of replaying history (a replaying patrol cries wolf daily).
check_lognew() {
  local label="$1" file="$2" pat="$3" off="$STATE_DIR/$label.offset" total offv new
  [ -f "$file" ] || { signals+=("$label=missing"); return; }
  total=$(wc -c < "$file" | tr -d ' ')
  if [ ! -f "$off" ]; then echo "$total" > "$off"; info+=("$label=baseline"); return; fi
  offv=$(cat "$off" 2>/dev/null || echo 0)
  if [ "${offv:-0}" -gt "$total" ]; then echo "$total" > "$off"; info+=("$label=rotated"); return; fi
  new=$(tail -c +"$((offv + 1))" "$file" 2>/dev/null | grep -cE "$pat")
  echo "$total" > "$off"
  if [ "${new:-0}" -gt 0 ]; then signals+=("$label=${new}hit"); else info+=("$label=clean"); fi
}

# state <label> <path> <max-age-seconds>  — a heartbeat file that must keep moving
check_state() {
  local label="$1" path="$2" maxage="$3" age mtime
  [ -e "$path" ] || { signals+=("$label=absent"); return; }
  # GNU first: there `stat -f` means --file-system, and it prints a banner to
  # stdout *before* exiting 1 — so `stat -f ... || stat -c ...` concatenates
  # both answers and the arithmetic blows up. Take the first purely numeric one.
  mtime=$(stat -c %Y "$path" 2>/dev/null)
  case "$mtime" in ''|*[!0-9]*) mtime=$(stat -f %m "$path" 2>/dev/null) ;; esac
  case "$mtime" in ''|*[!0-9]*) signals+=("$label=unreadable"); return ;; esac
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -gt "$maxage" ]; then signals+=("$label=stale${age}s"); else info+=("$label=${age}s"); fi
}

# ── run the configured checks ─────────────────────────────────────────────
# CHECKS is an array of "kind|label|arg1|arg2" strings set by the config file.
for spec in "${CHECKS[@]:-}"; do
  [ -z "$spec" ] && continue
  IFS='|' read -r kind label a b <<< "$spec"
  case "$kind" in
    http)   check_http "$label" "$a" "${b:-200}" ;;
    cmd)    check_cmd "$label" "${a:-60}" bash -c "$b" ;;
    lognew) check_lognew "$label" "$a" "$b" ;;
    state)  check_state "$label" "$a" "${b:-600}" ;;
    *)      signals+=("unknown-check:$kind") ;;
  esac
done

# ── output ────────────────────────────────────────────────────────────────
if [ ${#signals[@]} -eq 0 ]; then
  echo "OK ${NAME} ${info[*]:-no-checks}"
  exit 0
fi
echo "SIGNAL ${NAME} ${signals[*]}"
printf '  detail: %s\n' "${info[*]:-}"
exit 2
