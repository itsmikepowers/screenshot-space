---
name: resume-work
disable-model-invocation: true
description: Resume a previously paused work session by loading the handoff document. Use when the user says "resume", "pick up where we left off", "continue from last time", "what was I working on", "load handoff", or at the start of a session when prior work may need to be continued. Use this whenever the user wants to get back into work that was previously paused with /pause-work.
---

# Resume Work

Load a handoff document from a prior session and help the user pick up where they left off.

## Step 0: Load the handoff

Run the load script to pull the handoff contents into context:

```bash
bash .claude/skills/resume-work/scripts/load-handoff.sh
```

If the script outputs `NO_HANDOFF`, tell the user there's no saved handoff to resume and stop here.

## Step 1: Orient

Read the handoff output and then:

1. **Verify the active files still exist** — quickly glob/read the files listed in the handoff to confirm they're still there and haven't changed dramatically since the handoff was written.
2. **Check git state** — run `git status -sb` and `git log --oneline -5` to see if any commits were made after the handoff (someone else may have continued the work).

## Step 2: Brief the user

Give the user a concise summary:

- What work was in progress
- Current state (does it match what the handoff says, or has something changed?)
- Recommended next step

Keep it short — the point is to get back to work, not to write a report. If everything matches the handoff, a few sentences is enough. If things have diverged (new commits, files changed), flag that.

## Step 3: Start working

Ask the user if they want to pick up from the suggested next step, or if priorities have changed. Then get to it.
