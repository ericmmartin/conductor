# Periodic skills

Two skills beyond the main SDLC pipeline. They run on a schedule or on-demand, not as part of the issue-to-ship loop.

## `/conductor:digest` — shipped-issues summary

Runs daily (or on whatever cron you set), aggregates everything that shipped across all watched repos in the last 24h. For each shipped issue:

- Title and issue link
- Version bumped to (from `/conductor:ship`'s output)
- Summary of changes (1–2 sentences, generated from the PR diff via Haiku)
- Suggested **post-deployment testing/validation steps** (parsed from a `post_merge:` section in the issue body if present, or generated from the acceptance criteria)
- Any new issues filed during the cycle (out-of-scope Qodo findings, follow-ups)

Output: a markdown document committed to a `docs/digests/{date}.md` file in the repo. Plus a notification to Teams-Bot / Discord with a summary + commit link.

```yaml
# in .conductor/profile.yml
digest:
  output: markdown   # alternatives: notification | both
  schedule: "0 18 * * *"   # daily 6pm, cron syntax
```

Per-ship summaries are already in the PR description block (immediate); the digest aggregates them for retrospective review.

## `/conductor:triage` — backlog hygiene (Phase 6)

Runs when new issues are filed (via GitHub webhook or periodic sweep) and checks each new issue against:

- **Open issues in the same repo** — semantic similarity via embeddings. If similarity > threshold to an existing issue, comment: "This looks like it might overlap with #42. Worth combining or differentiating?"
- **Recently shipped issues (last 90d)** — check if the requested change was already done. If similarity is high, comment: "This was shipped in #38 (v1.4.2). Is something missing or different now?"
- **Open issues with file-overlap potential** — if the new issue's acceptance criteria mention paths/modules that another open issue is in-flight on, flag as a potential conflict ("Conductor is currently working on #51, which touches `src/auth/`. This issue also touches that area — consider sequencing.")

Output: comments on the new issue with findings. Does NOT block — humans decide whether to close, combine, or proceed.

Implementation deferred entirely to Phase 6.
