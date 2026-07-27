# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the glossary (Profile, PIN, Gateway, Root Helper, Cert Pin, Status Detection, Tunnel 状态, Keychain Key).
- **`docs/adr/`** — read ADRs that touch the area you're about to work in (e.g. 0001 openconnect-path-not-user-configurable, 0002 cert-pin-tofu).

If any of these don't exist, **proceed silently** — don't flag their absence; don't suggest creating them upfront. `/domain-modeling` creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context (this repo):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-openconnect-path-not-user-configurable.md
│   └── 0002-cert-pin-tofu.md
└── ...
```

## Use the glossary's vocabulary

When your output names a domain concept (issue title, refactor proposal, hypothesis, test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding.
