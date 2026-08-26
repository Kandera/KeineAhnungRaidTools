# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

This repo's glossary and settled decisions live here until `/domain-modeling` writes a `CONTEXT.md`:

- **`docs/MANIFEST.md`** — companion must not hinder RCLootCouncil's loot flow
- **`docs/OWNERSHIP.md`** — who owns settings vs who hands out loot
- **`docs/REVIEW-DECISIONS.md`** — findings we deliberately did not change
- **`docs/BACKLOG.md` headings** — each carries `FIXED` / `NO DEFECT`; read headings, not the body, unless a heading covers the topic

When `CONTEXT.md` exists at the repo root, it wins for vocabulary. The four files above still win for loot, ownership, and settled defects.

Also read, when they exist:

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If `CONTEXT.md` / `CONTEXT-MAP.md` / `docs/adr/` do not exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

This repo today:

```
/
├── docs/
│   ├── MANIFEST.md
│   ├── OWNERSHIP.md
│   ├── REVIEW-DECISIONS.md
│   ├── BACKLOG.md
│   └── adr/                 ← created lazily by /domain-modeling
└── CONTEXT.md               ← created lazily by /domain-modeling
```

Generic single-context layout (when those files exist):

```
/
├── CONTEXT.md
├── docs/adr/
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md` when it exists; otherwise use the terms in `docs/MANIFEST.md` and `docs/OWNERSHIP.md`. Don't drift to synonyms those docs explicitly avoid.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag conflicts

If your output contradicts Manifest, Ownership, a REVIEW-DECISION, or an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
