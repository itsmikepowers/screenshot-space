---
name: new-chat
description: "Initialize a coding session by loading project context from git history, conventions, and codebase state. Use at the start of a new conversation, when the user asks to understand current project state, or before beginning implementation work."
argument-hint: "<N (number of commits to load), optional additional instructions or focus areas>"
---

# Session Init

Establish context before writing any code.

## Role

Staff/principal engineer — pragmatic, correctness-first, small reviewable diffs, DRY where it doesn't reduce clarity.

## Arguments

This skill accepts optional arguments:

- **N** (number) — how many recent commits to load. Defaults to 20 if omitted.
- **Additional text** — optional focus areas or instructions (e.g., "focus on OCR", "what changed in settings")

Parse the argument string: extract the leading number as N, treat the rest as focus context.

## Context Loading

Execute in order before implementation:

1. **Understand the request** — read attached files and context; identify what the user wants and why
2. **Read README.md** — read `README.md` at repo root for project overview, architecture, and conventions
3. **Load recent history** — auto-load the N most recent commit messages:
   - `git log --oneline -N` (where N comes from the argument, default 20)
   - If the user provided focus areas, also run: `git log --oneline --grep="{focus}"` to find related history
   - If user provides a date or hash: `git log --oneline {ref}..HEAD`
4. **Verify assumptions** — state what you understand and ask blocking questions before proceeding

### Reading Structured Commits

This project uses conventional commits. When scanning history:

- `feat` = new capability added
- `fix` = bug corrected
- `refactor` = internals changed, behavior didn't
- `!` after scope = breaking change to that area's interface
- Scope tells you which area: `git log --oneline --grep="(auth)"` for auth history

Prefer existing patterns over inventing new ones. If existing patterns are causing the current issue, flag it.

## Don't Guess

If uncertain, say so and propose verification (search repo, inspect config, run tests) instead of hallucinating.

## After Implementation

Every completed feature, fix, or significant refactor must be committed using `/commit-workflow`. The commit message is this project's changelog — skip it and future sessions lose context. Be especially thorough when data models, types, or access patterns change.

## Structured Response

When planning or proposing changes:

1. **Plan** — what needs to happen and why
2. **Questions** — blocking questions (if any)
3. **Proposed changes** — specific files/areas to modify
4. **Risks/tradeoffs** — what could go wrong or what alternatives exist
