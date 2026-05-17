# ADR 006 — Public OSS repo from day one, unpromoted

**Status:** Accepted
**Date:** 2026-05-15

## Context

The user's stated posture is "personal-use first, OSS later." The original interpretation was: keep the repo private through the early phases, flip to public around Phase 5 when the schema is stable and the docs are written.

Reconsidered: the cost of going public on day one is small but real (more discipline around what gets committed — no secrets, no hardcoded user paths, no internal references). For a personal-use tool, that's the right discipline regardless of visibility.

The benefit of going public on day one is that it forces those habits from commit 1. The alternative — go private now, flip public at Phase 5 — means auditing every commit retroactively to scrub anything that shouldn't have been there. Public-from-start avoids that entirely.

Critically: **public ≠ promoted.** A repo can exist publicly without inviting traffic.

## Decision

The conductor repo is public on GitHub from day one. Until Phase 5:

- No README banner saying "production-ready, use this!"
- No plugin marketplace listings.
- No Hacker News post.
- No CONTRIBUTING.md, no issue templates, no roadmap public statement.
- License is MIT (file present from day one).

The repo just exists. People who find it can use it. The owner is not soliciting attention or contributions.

When Phase 5 lands (stable schema, multiple repos using it):

- Polish the README.
- Add CONTRIBUTING.md, issue templates, a code of conduct.
- Optionally publish to public npm.
- Announce.

## Consequences

**Positive:**
- Forces secret hygiene and hardcoded-path discipline from the start.
- No "history rewrite to scrub secrets" later.
- The act of public commit is a healthy filter — "would I be comfortable with someone seeing this?"
- License is decided once and lives in the repo.

**Negative:**
- Casual discoverability — someone might find it and try it before it's stable. Mitigated by README framing ("pre-Phase 0, code not yet written").
- Minor pressure of "this is public" even when the owner doesn't want eyes on it. Mitigated by not promoting.

## Alternatives considered

- **Private now, flip later** — requires retroactive audit; loses the discipline forcing function.
- **Public + actively promoted** — wrong for the personal-use-first posture; invites distractions.

## License

MIT. Shorter, more permissive, standard for dev tools. Apache 2.0's patent grant is only worth the extra ceremony for big-company contributions, which aren't relevant here.

## Related

- See [README.md](../README.md) for the public-facing framing.
- See [phased-plan.md](../docs/phased-plan.md) for what Phase 5 entails.
