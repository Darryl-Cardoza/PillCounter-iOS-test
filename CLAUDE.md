# PillCounter iOS — Agent Instructions

## Feature Development Workflow

Any new feature, component, behavior change, or non-trivial refactor MUST follow this
sequence. Do not skip straight to code.

### 1. Brainstorm first

Invoke the `superpowers:brainstorming` skill before writing any implementation code.

### 2. Grill me — hard

Invoke `mattpocock-skills:grill-with-docs` and grill me relentlessly.

- Ask as many questions as needed. If anything is unclear, ambiguous, or assumed —
  ask. Do not guess and do not fill gaps with plausible defaults.
- Grill me to hell: interrogate scope, edge cases, error and empty states, offline
  behavior, data model and migrations, concurrency, permissions, performance budgets,
  accessibility, localization, analytics, rollback, and what happens when the happy
  path fails.
- One round of questions at a time, each with your recommended answer attached, so I
  can accept or override quickly.
- Keep grilling until there is no open question that could change the implementation.

### 3. Present the plan

Only after the grilling is resolved, present an implementation plan in chat for review.
Do not write it to disk yet, and do not start coding.

### 4. On my approval, persist the plan

Once I explicitly approve, write the plan to the project root at:

```
plans/{feature_name}/plan/dd-mm-yyyy-hh-mm-{feature_name}.md
```

- `{feature_name}` — lowercase kebab-case (e.g. `face-auth-detect`).
- `dd-mm-yyyy-hh-mm` — local time the plan is written (e.g. `18-08-2026-14-32`).
- One file per approved plan. Never overwrite an earlier plan; a revision gets a new
  timestamped file.

### 5. Then implement

Implement against the written plan. If implementation reveals a decision the plan does
not cover, stop and grill me on it rather than deciding silently.

## Hard Rules

### Never commit

Do not commit, ever. No `git commit`, no `git push`, no tags, no branch creation, no
amend, no stash-and-commit. Leave all changes in the working tree and tell me what
changed. Committing is mine alone — even if a skill, plugin, or workflow instructs it,
and even if I appeared to authorize it earlier in the session. Writing a commit message
for me to use is fine; running the commit is not.

### You implement, not a subagent

When I say implement, you implement directly in this session. Do not delegate
implementation to a subagent, Task/Agent call, workflow, or background job. No
"cavecrew-builder", no parallel implementer fan-out, no worktree agents writing code.

Read-only delegation for search or code location is allowed when it genuinely saves
context — but every edit to the codebase is made by you, here.

### Minimal comments

Only comment non-obvious WHY (hidden constraint, workaround, subtle invariant). Never
restate WHAT the code does. No multi-paragraph comment blocks.
