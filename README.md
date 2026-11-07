# agent-ops-kit

Ops patterns for agent fleets that run on small, boring machines — the kind that
OOM at 900 MB and where every LLM token is budget.

Two things are in here:

1. **Script-first patrols** (`bin/patrol.sh`) — a scheduler runs a shell script;
   the model is only woken when the script prints `SIGNAL`. A normal round costs
   one line of output instead of 28 model turns.
2. **A review gate** (`bin/review-gate.sh`) — deploys are refused unless a code
   review and a security review were signed *for that exact tree hash*. Editing
   one line invalidates both signatures.

## Why (measured, 2026-11)

Running three "read the log and report" patrols every 3–6 hours cost, per round,
up to **6M input tokens and 28 model turns**. **59% of the tool calls were pure
collection** (ssh, curl, grep, status codes) — work a script does for free and
without variance. After moving collection into a script: 1–2 turns per normal
round, and the model only sees the cases that need judgement.

The other half is about honest signals. On a 900 MB box, out-of-memory kills are
*normal*; a patrol that alarms on every one is noise, and noise trains the
operator to ignore the alarm. The rule both scripts encode:

> A condition that is expected to be true most of the time is **counted**, never
> raised. Only a change of state raises.

## Install

```sh
git clone <this repo> && cd agent-ops-kit
cp examples/patrol.conf.example patrol.conf   # edit hosts, paths, thresholds
./bin/patrol.sh patrol.conf                   # prints OK ... or SIGNAL ...
```

Nothing here needs a daemon, a database, or a language runtime beyond bash,
curl and coreutils. The review gate needs `shasum`/`sha256sum`.

## What this is not

- Not an agent framework. It sits under whatever scheduler you already use
  (cron, systemd timer, GitHub Actions) and under whatever model loop you run.
- Not a monitoring service. No dashboards, no retention, no alerts pipeline —
  it prints one line and exits non-zero on `SIGNAL`.
- Not a security product. The review gate records *that* a review happened and
  *what it said*; it cannot make a review good.

## Status

Extracted from a live fleet (3 agents, 45+ days uptime). The scripts here are
generic versions; host names, keys and private paths were removed.
