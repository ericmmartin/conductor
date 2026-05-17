# ADR 002 — YAML over XML for the profile format

**Status:** Accepted
**Date:** 2026-05-15

## Context

The per-repo profile (`.conductor/profile.yml`) is read by both shell skills (via `yq`) and the TypeScript orchestrator (via the `yaml` npm package). It contains a mix of structured fields (stack, gates, model routing, thresholds) and prose (notes). Humans edit it by hand; Claude reads it as context when invoked.

An early proposal suggested XML tags inside `.conductor/profile.xml`, on the reasoning that "HTML-style structured tags are the go-to for LLM context." That conflated two things:

1. **Inside the LLM context window**, XML-style tags do help Claude parse structured input. This is a prompt-engineering pattern.
2. **For config files on disk**, XML is verbose, parser-hostile for shell, and unfamiliar to anyone outside of Java/.NET ecosystems.

The right format for the profile is the one that's ergonomic for humans editing on disk AND has clean tooling in both shell and TS. That's YAML.

## Decision

The profile lives at `.conductor/profile.yml`. Plain YAML — comment-supporting, multiline strings for prose, standard parsers in every language. One shared schema defined in `shared/profile-schema.ts` (Zod), validated on every load.

Per-issue overrides stay as plain keyword lines in the GitHub issue body (`semver: patch`, `model: opus`), parsed by line prefix. No structured block needed inside the issue.

## Consequences

**Positive:**
- `yq` and the `yaml` npm package are battle-tested, ubiquitous, well-documented.
- Comments work natively — humans can annotate decisions inline.
- Multiline strings for prose are clean.
- Zod schema in `shared/` is the single source of truth; both packages import it.

**Negative:**
- YAML's whitespace-sensitivity occasionally bites editors who don't have visible-whitespace turned on. Mitigated by linting the profile on every load and producing a clear error.

## Alternatives considered

- **XML** — verbose, less ergonomic for hand-edit, needs more tooling on the shell side. Rejected.
- **JSON** — no comments, no multiline strings, awkward for humans. Rejected.
- **TOML** — fine for config, but the TS ecosystem leans YAML; less idiomatic. Rejected.
- **JS/TS config file** — code-as-config is powerful but adds an import boundary, and the profile is genuinely declarative. Rejected.
- **Markdown with YAML front-matter** — works for tools like Hugo/Astro, but adds a parsing layer and the prose section is short enough to fit cleanly in a YAML `notes` field. Rejected.

## Related

- See [profile-reference.md](../docs/profile-reference.md) for the full schema.
