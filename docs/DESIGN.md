# Design notes

## The measurement that started this

Three patrols ("read the log, report") ran every 3–6 hours. Across 20 rounds the
model consumed 97.9M input tokens and 510 assistant turns; **126 of 212 tool
calls (59%) were pure collection** — ssh, curl, grep, status counts. The site
patrol was the worst at 90%.

Moving collection into a script turned a normal round into: run script, read one
line, reply. The model now spends turns only where judgement is needed.

## Three rules for signals

1. **Chronic conditions are counted, never raised.** A 900 MB host that OOM-kills
   its agent every hour is not an incident; it is the environment. Raised every
   round, it becomes wallpaper.
2. **Only a change of state raises.** `lognew` compares against a byte offset and
   resets the baseline when the file rotates. A patrol that replays history cries
   wolf once a day.
3. **A signal must be actionable by the model.** "Load average is 6" is not
   actionable there. "The process that should be running is not, here is its last
   20 lines" is.

## Why the review gate hashes the tree

Two reviews signed against a branch name are worthless: the next commit inherits
both. Hashing the source tree binds each signature to exact bytes, so any edit
invalidates them and the deploy script refuses. Evidence is a file, not a promise.

## Non-goals

No config language, no plugin system, no daemon, no alert routing.
