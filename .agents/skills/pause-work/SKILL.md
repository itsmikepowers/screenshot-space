---
name: pause-work
disable-model-invocation: true
description: Create a handoff document to pause your current work session and pick it back up later. Use when the user says "pause", "stepping away", "going to bed", "save progress", "handoff", "pick this up later", "context is getting long", or when the context window is getting full and work needs to be captured before starting fresh.
argument-hint: "Focus this handoff on"
---

# Pause Work

Create a handoff document that captures the current work state so a future session can resume seamlessly.

## Step 0: Clear the handoff file

Run the clear script first — this ensures a blank slate without wasting tokens on deletion:

```bash
bash .claude/skills/pause-work/scripts/clear-handoff.sh
```

## Step 1: Gather context

The user will typically provide direction alongside the skill invocation — e.g., "I want to capture where we are with the analytics refactor and the open bug with the chart." This user-provided context is your primary guide for what to focus on. Use it to steer which parts of the conversation you emphasize, which files you highlight, and what the "next steps" should center around.

If the user doesn't provide any direction, fall back to inferring from the conversation.

Between the user's direction and the conversation history, identify:

- What work was being done (feature, bug fix, refactor, investigation)
- Which files were being actively worked on
- What the current state is (working? broken? partially implemented?)
- Any specific errors, symptoms, or behaviors observed (facts only)
- What the next steps would be if work continued

## Step 2: Write the handoff

Write the handoff to `.blueprint/handoff/handoff.md` using this structure:

```markdown
# Handoff — [Date]

## What we were doing
[1-2 sentences describing the task]

## Active files
- `path/to/file.ts` — [what role this file plays in the current work]
- `path/to/other-file.ts` — [why this file matters]

## Current state
[Is the feature half-implemented? Is there a bug we're tracking down? What works and what doesn't?]

## Known facts
[Only things that have been directly observed or confirmed — not theories or guesses]
- [Fact 1]
- [Fact 2]

## Next steps
[What should happen next when work resumes]
1. [Step 1]
2. [Step 2]
```

### Writing guidelines

The handoff will be read by a fresh Claude session with zero context about this conversation. Write it so that session can hit the ground running.

- **Facts only** — if something was observed (an error message, a behavior, a test result), include it. If it's a hypothesis about why something is happening, leave it out. Theories from a prior session can mislead a fresh one.
- **File paths are critical** — always include the full relative path from the project root. These are the anchors that let the next session orient itself.
- **Be specific but concise** — "the `LinkClicksList` component renders an empty list when `timeRange` is `7d`" is good. "There's a bug in the analytics page" is not.
- **Include error messages verbatim** if they're relevant — copy-paste, don't paraphrase.
- **Next steps should be actionable** — "investigate why X returns null" is better than "fix the bug."
