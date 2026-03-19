---
name: commit-workflow
description: Author structured, machine-readable git commits that serve as a project changelog and state tracker for AI agents. Use after completing features, fixes, refactors, or any code changes. Also use when the user asks about commit conventions, git workflow, or version control.
---

# Git Changelog

**Commit outcomes, not process.** The git log reads like a changelog of what shipped, not a diary of what was attempted.

## Step 1: Gather Context

- `git status -sb` — modified/deleted/untracked files + current branch
- `git diff` — unstaged changes
- `git diff --cached` — staged changes
- `git diff --check` — catch whitespace errors or merge conflict markers

If changes span staged and unstaged, use `git diff HEAD` for a combined view. To compare a file to its prior state: `git show HEAD:<path>`.

Skip this step only if you authored the changes and already have full context. If you are not the author, this step is imperative.

## Step 2: Analyze Changes

Identify:

- What feature, fix, or refactor was implemented
- Which files were modified, created, or deleted
- The "why" behind each change
- Any related cleanup (dead code removal, dependency updates)

If the session produced multiple unrelated changes, plan separate atomic commits — one logical change per commit.

## Step 3: Stage Selectively

Never use `git add .` or `git add -A` unless explicitly instructed.

- `git add <path...>` — stage specific files
- `git add -p <path>` — stage individual hunks within a mixed file
- `git restore --staged <path>` — unstage if needed
- `git diff --cached --name-only` — confirm what's staged before committing

**Do not stage:**

- `.env`, credentials, API keys, or secrets
- Generated artifacts reproducible from source
- Temporary debugging code
- Unrelated changes (save for a separate commit)

## Step 4: Write Commit Message

### Format

```
{type}({scope}): {imperative description}

{body — what was done and why}

Changes:
- {area}: {specific description}
```

Use HEREDOC for multi-line messages:

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add email format validation

Implement RFC 5322 validation before account creation to prevent
invalid emails from reaching the verification service.

Changes:
- auth/validators.ts: add `validateEmail()` with RFC 5322 regex
- auth/register.ts: call validator before creating account record
- auth/types.ts: add `ValidationError` type for structured error responses
EOF
)"
```

### Types

| Type | When | Changelog section |
|------|------|-------------------|
| `feat` | New user-facing capability | Added |
| `fix` | Bug fix | Fixed |
| `refactor` | Internal restructure, no behavior change | Changed |
| `perf` | Performance improvement | Improved |
| `test` | Add or update tests only | — |
| `docs` | Documentation only | — |
| `style` | Formatting, linting, no logic change | — |
| `chore` | Dependencies, config, tooling | — |
| `build` | Build system or CI changes | — |

### Scope

Scope identifies the area affected. Check `git log --oneline -30` and reuse existing scopes before inventing new ones.

- Feature area: `feat(auth)`, `fix(payments)`, `refactor(db)`
- Module/package: `feat(api)`, `fix(cli)`, `chore(deps)`
- Component: `feat(sidebar)`, `fix(modal)`

### Title (first line)

- Imperative mood, lowercase: "add" not "Added" or "Adds"
- Max 72 characters
- Describe the **outcome**, not the implementation

### Body

- Explain WHAT was done and WHY
- Note decisions, trade-offs, or architectural evolution
- Flag data model, type, or access pattern changes with extra detail

### Changes List

- Group by file or logical area
- Be specific: "Added `popOutEnabled` field to `LinkBlock` type in `src/types/pages.ts`" not "Updated types"
- Include deleted files/code explicitly
- This list is the detailed changelog — make it comprehensive and accurate

### Breaking Changes

Append `!` after scope: `feat(api)!: change auth token format`
Include `BREAKING CHANGE:` footer with migration info.

## Step 5: Update Documentation

After committing, check whether the change requires updates to project documentation. The scope depends on the commit type — not every commit needs every update.

### README.md

Read `README.md` and check each section against what just changed:

| Commit type | What to check in README |
|---|---|
| `feat` | **Features** section (new capability?), **Usage** table (new hotkey/interaction?), **Configuration** table (new setting?), **Architecture** tree (new source file?) |
| `fix` | Only if user-facing behavior changed (e.g., a workaround in Troubleshooting is no longer needed) |
| `refactor` | **Architecture** tree only — if source files were added, renamed, or deleted |
| `build`/`chore` | **Installation** or **Distribution** sections — if build commands, dependencies, or install steps changed |
| `docs` | By definition — the README is likely the target |
| `test`/`style`/`perf` | Usually nothing. Skip unless the change is user-visible. |

For the **Architecture tree** specifically: run `ls Sources/` and compare against the tree in README. If any files were added, removed, or renamed, update the tree to match. Each entry should have a brief `# comment` describing the file's role.

If no README sections need updating, skip this — don't touch the README just to touch it.

### Release (Version Bump + DMG Build)

The app has an in-app updater that checks the `releases/` directory on GitHub for new DMG files. For users to receive updates, a new versioned DMG must be committed and pushed. This means every commit that changes app behavior needs a release.

#### When to release

**Release required** — any commit that modifies files in `Sources/`, `Info.plist`, `Package.swift`, or `Assets/`. These change what the app does, so users need the update.

**No release** — changes that only touch documentation or dev tooling. Specifically, skip the release for changes limited to:
- `README.md`, `docs/`, or any markdown files
- `.claude/`, `.agents/`, `.blueprint/`
- `dev.sh`, `Makefile` (dev targets only), `.gitignore`
- `scripts/` (build scripts don't affect the running app)

If a commit touches both app code and dev-only files, it still needs a release (the app code is what matters).

#### Version number rules

Read the current version from `Info.plist` (`CFBundleShortVersionString`). The format is `MAJOR.MINOR.PATCH`.

| Bump | When | Example |
|------|------|---------|
| **MAJOR** (X.0.0) | User explicitly says this is a major release or a huge feature | 1.0.2 → 2.0.0 |
| **MINOR** (x.Y.0) | User explicitly says this is a significant feature or big update | 1.0.2 → 1.1.0 |
| **PATCH** (x.y.Z) | **Default for everything else** — bug fixes, small features, tweaks, refactors that change behavior | 1.0.2 → 1.0.3 |

The default is always PATCH. Only bump MAJOR or MINOR if the user explicitly says so. Don't ask — just bump PATCH unless told otherwise.

#### Release steps

After the main commit is verified, perform these steps:

1. **Bump the version** in `Info.plist` — update both `CFBundleVersion` and `CFBundleShortVersionString`
2. **Update version references** in `README.md` — DMG download links, version badges, any hardcoded version strings (e.g., `ScreenshotSpace-1.0.2.dmg` → `ScreenshotSpace-1.0.3.dmg`)
3. **Update the `VERSION` default** in `Makefile` (the `VERSION ?= x.y.z` line)
4. **Build the DMG**: `VERSION={new_version} make dmg`
5. **Remove the old DMG** from `releases/` and **add the new one**: `git rm releases/ScreenshotSpace-{old}.dmg` then `git add releases/ScreenshotSpace-{new}.dmg`
6. **Commit everything together**:
   ```
   chore(release): bump version to {new_version}
   ```
   Stage: `Info.plist`, `README.md`, `Makefile`, `releases/ScreenshotSpace-{new}.dmg`

This keeps the release atomic — one commit has the version bump, the updated README references, and the distributable DMG all together.

## Step 6: Verify

- `git show --stat` — review exactly what was committed (your receipt)
- `git log --oneline -5` — confirm it appears in history

If multiple atomic commits were planned, repeat Steps 3–6 for each.

## Branching

Choose one strategy per project and stay consistent:

| Strategy | Pattern | When |
|----------|---------|------|
| **none** | Current branch | Solo, small projects |
| **feature** | `feat/{scope}-{slug}` | Team projects, parallel work |
| **release** | `release/v{X.Y}` | Formal releases |

Merge with `--no-ff` to preserve branch topology in the log.

## Release Tagging

```bash
git tag -a v{X.Y.Z} -m "v{X.Y.Z} {Release name}

- feat(scope): notable feature
- fix(scope): notable fix"
```

## AI Agent Parsing Guide

Structured commits make git history queryable:

- **`git log --oneline`** → ordered changelog of shipped outcomes
- **`git log --oneline --grep="feat"`** → all features added
- **`git log --oneline --grep="fix"`** → all bugs fixed
- **`git log --oneline --grep="{scope}"`** → full history of one area
- **`git tag -l -n1`** → release timeline with summaries
- **`git log --oneline v1.0..v1.1`** → what changed between releases

Regex for extraction: `^(feat|fix|refactor|perf|test|docs|style|chore|build)(\(.+\))?!?: .+$`
