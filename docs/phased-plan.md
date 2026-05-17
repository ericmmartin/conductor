# Phased build plan

Each phase ends with a working artifact you can use and reassess. No calendar estimates — the only real constraint is Claude session tokens, and you'll burn through them at whatever pace your concurrency and gates allow.

## Phase 0 — Spike

Empty repo, `packages/plugin` with a minimal `/conductor:work` that reads `profile.yml`, claims an issue via label swap + Project status update, creates a worktree (always), runs `claude -p` with a one-line prompt, writes result JSON.

**End state:** the skeleton end-to-end pipeline runs once successfully on a throwaway issue.

## Phase 1 — Plugin-only viable

Port `/spec`, `/work`, `/address`, `/ship`, `/reflect`, `/status`, `/init` from the predecessor with the trimmed result envelope and the YAML profile parser. Wire subagent reviewers, the quality-gate runner, and the worktree-prompt-in-manual-mode.

**End state:** you can run the full SDLC manually from your laptop on a real issue without the daemon.

## Phase 2 — Orchestrator MVP

Port the predecessor's poller (extend to multi-repo, slot-based concurrency with sequential-per-project, FIFO across competing projects), DAG scheduler (extend to cross-repo union graph), result-file reader, graceful shutdown. Port the session-utilization probe (preserve nsanden attribution). Add the four gates (usage with 80/85/90 thresholds, rate-limit, active-hours, manual-pause), model router, reconciler (Project status wins on conflict), and JSONL event log. Wire Teams-Bot + Discord notifications. Add `/status` JSON endpoint and the static HTML page.

**End state:** the first project runs unattended on the new orchestrator.

## Phase 3 — Qodo loop + workflow modes

Implement the wait-30s → check-for-Qodo → fallback-to-`/agentic_review` flow with the existing-comment short-circuit. Build `/conductor:address` to iterate Qodo's individual comments, decide validity, fix or rebut, reply per-comment, resolve threads. Wire `ship_when_green` and `deploy_and_validate` modes in `pr-monitor.ts`. Wire `:validated` label semantics. Implement out-of-scope finding → new issue creation. Implement the `skip-code-review` opt-out label.

**End state:** a full SDLC cycle (issue → PR → Qodo → address → `:validated` → merge → ship) runs end-to-end with the orchestrator handling every transition.

## Phase 4 — Second project + digest + token reporting

Onboard a second repo (different stack — likely the Next.js one). Wire `/conductor:digest` for daily shipped-issues summaries. Wire `/conductor:usage` and `/conductor:reflect-usage` for per-skill token reporting and optimization suggestions. Active-PR adaptive polling.

**End state:** two projects run side-by-side at concurrency 2, each respecting sequential-per-project; you get a daily digest and can introspect token spend per skill.

## Phase 5 — OSS readiness

When you have multiple repos using it and the profile schema has been stable across them: write the docs (this `docs/` set, expanded), add CONTRIBUTING.md and issue templates, set up CI for conductor itself, optionally publish to public npm, announce.

**End state:** the repo is discoverable and a stranger could plausibly use it on their own project.

## Phase 6 — Backlog hygiene (`/conductor:triage`)

Add the embedding-based similarity check for new issues against open and recently-shipped ones. Add the file-overlap conflict flag.

**End state:** filing a new issue triggers a comment within ~1 min if it looks like a dup or overlaps an in-flight issue.

## Open questions to resolve along the way

These are deferred from current decisions; flag them when relevant.

**Reconciler conflict resolution.** Labels and Project status drift gets reconciled toward Project status (you manage the board, orchestrator follows). Validate the resolution path doesn't surprise you.

**Qodo trigger via non-author user.** Confirm in Phase 3 that posting `/agentic_review` from your authenticated user account actually triggers Qodo on a bot-authored PR. If it requires author-origin, the orchestrator needs the bot account to post the trigger, which means a second PAT in env.

**Qodo "review started" signal format.** The 30-second wait depends on detecting Qodo's "review in progress" comment by pattern. Validate the exact format in Phase 3 and lock the poll predicate to it.

**Cross-project dependency churn.** With the union DAG enabled, a single repo's slow-to-merge issue can block dependents in multiple other repos. The `:blocked-dependency` label makes this visible, but you might want a "this dep has been blocking for >X days" notification. Defer until you observe whether it actually happens.

**Resolved from earlier rounds:**

- *Live session-utilization probe* — code exists in the predecessor, attributed to [nsanden/claude-rate-monitor](https://github.com/nsanden/claude-rate-monitor). Port as-is.
- *`feature_url_pattern`* — not needed; CI handles deploy URL surfacing where applicable.
- *FIFO starvation* — impossible by design. Each project gets at most one slot, so a high-volume project can't dominate.
