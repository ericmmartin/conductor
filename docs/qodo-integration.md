# Qodo integration

Qodo (`qodo-code-review` bot) is conductor's only code-review reviewer in scope today. Codex and others are deferred — the `reviewers` config is generalized so adding them later is one profile change, not a code change.

This doc covers: bot account decisions, when review is required vs skipped, the wait/trigger flow, and how `/conductor:address` consumes Qodo's findings.

## Bot account (mostly: don't)

**Default: don't use one.** Run the orchestrator under your own GitHub user (`ericmmartin`). PRs open as you, Qodo's automatic review usually fires on PR open, no manual trigger needed. Simpler PAT setup (just yours), simpler audit trail.

Only use a bot account when branch protection rules require a separate approver from the PR author, and you want the orchestrator to open PRs that you (the human) can approve. In that case create a machine user, set its PAT as `GITHUB_TOKEN_BOT` in env, and add `author: bot` to the per-repo profile. The decision is per-repo, not global.

```yaml
author: user      # default; PRs open as the daemon's authenticated user
# or
author: bot       # adds /agentic_review trigger after PR open
```

## Should this PR get reviewed at all?

Default: **review every PR** (safe; never silently skips a real review need). Opt-out per-issue via a label set at issue creation time:

```yaml
# in .conductor/profile.yml
review:
  default: required          # alternatives: skip
  skip_label: skip-code-review
  start_wait_seconds: 30
```

If the source issue has `skip-code-review`, the orchestrator does not wait for or trigger Qodo on its PR — it goes straight to ship logic (or human merge for `deploy_and_validate` mode).

LOC limits and `[skip ci]` markers are deliberately *not* used as the signal: a 5-line change can be more dangerous than a 500-line refactor, and skip-CI is about CI, not code review. A label on the issue is explicit, human-controlled, and visible in the GH UI.

If you want the opposite polarity (review off by default, opt-in via `requires-code-review`), flip `review.default: skip` and rename the label field. Same machinery.

## The wait/trigger flow

Important: **Qodo does not use GitHub's formal "request changes" review mechanism.** It posts inline comments on the diff and a summary comment. The orchestrator has to read those comments and act on each one, not poll for a `CHANGES_REQUESTED` review state.

Flow after PR creation. The orchestrator always checks existing PR comments before any trigger logic — if Qodo has already posted a final review on this PR, skip all of this and go straight to address:

1. **Open PR.**
2. **Check PR comments.** If a `qodo-code-review` final review comment already exists, skip to step 5.
3. **Wait 30 seconds** (configurable via `review.start_wait_seconds`). Poll PR comments for Qodo's "review in progress" comment.
4. **If Qodo started within 30s:** wait for the final review comment.
   **If not:** post `/agentic_review` from the authenticated user account (`ericmmartin`, not the bot). Poll for "review in progress," then wait for completion. If still no Qodo activity 60s after trigger → escalate (notify + label PR `:blocked-review` + free slot).
5. **Review complete.** Proceed to address.

The orchestrator will not trigger Qodo again on this PR; the comment-existence check at step 2 covers re-poll cycles, even if address commits push new code.

The `/agentic_review` trigger is always posted as `ericmmartin` (the authenticated user), not as the bot account. Sidesteps any "trigger must come from PR author" requirement Qodo might have.

## Addressing Qodo's findings

The orchestrator dispatches `/conductor:address` with the full set of Qodo comments. The skill:

1. **Enumerates each Qodo comment** on the PR (inline + summary).
2. **For each comment, decides validity:**
   - **Valid finding:** implement the fix.
   - **Invalid / disagree:** prepare a reasoned rebuttal.
   - **Out of scope:** create a new GitHub issue with the finding + PR link + Qodo's suggested fix, labeled `conductor:ready`.
3. **Reply to each Qodo comment individually** with what was done. Examples:
   - "Fixed in `<commit>`. Renamed `getX()` to `fetchX()` to match the surrounding convention."
   - "Disagree — `Math.floor()` is correct here because we want truncation, not rounding. Leaving as-is."
   - "Out of scope for this PR. Filed as #214 for follow-up."
4. **Resolve the comment thread** on GitHub (mark conversation as resolved) for any comment where the fix is in or the discussion is settled. Leave it open if the rebuttal might invite further discussion.
5. **Push all fixes as one commit** to the PR branch (or one commit per logical group — TBD by skill behavior).
6. **Done.** The orchestrator does not re-trigger Qodo. Any new issues introduced by the address commits are caught by CI or human review at merge time.

This is one-pass Qodo by design. Avoids the back-and-forth loop where Qodo finds → fix → Qodo finds again → fix again. One review, one address, ship. If something was genuinely missed, it becomes a future issue, not a blocker on this PR.

See [ADR 004 — One-pass Qodo](../adrs/004-one-pass-qodo.md) for the rationale.

## Open question (Phase 3 to confirm)

Does Qodo accept `/agentic_review` triggers from a non-author user? If the trigger must come from the PR author, then for `author: bot` repos we need the bot account to post the trigger (a second PAT in env). Test in Phase 3 before relying on the current design.
