---
name: repository-maintenance
description: Organize or maintain Manuscript packages, shared guidance, embedded inputs, tool/version pins, CI, licenses, and standalone releases.
---

# Repository maintenance

Use for cleanup, package moves, pins (`scripts/devtools.env`, `.go-version`, `.msversion`), CI/releases, or the skill catalog. Read [architecture](../../documentation/contributing/architecture.md), [maintenance](../../documentation/contributing/maintenance.md), and [lessons](../../.experts/repository.md).

- Simplify duplicated traversal, queries, serialization, forwarding, and CLI paths as well as layout. Name the work removed; add a layer only for a concrete contract.
- Respect ownership/public import paths, `scripts/repo-check/policy.json`, frontend isolation, and exhaustive checked/lowered syntax kinds.
- Moves update imports, embed inputs, implementation hashes, release filters, docs, and tests. Root embed sources remain beside `go.mod`/`vendor` where Go embed rules require it.
- Use pinned `.go-version`, `.node-version`, tool manifests, and Makefile commands. Standalone behavior cannot rely on host tools. Publish caches only after complete archive validation, with no partial ready state.
- After third-party changes run `make licenses` and `make licenses-check`. Update generated outputs through their owner.
- Keep guides/site inputs separate from ignored books, caches, SDKs, coverage, and releases; do not restore tracked generated website HTML.
- Catalog edits follow [skill maintenance](../README.md#maintain-the-catalog): one AGENTS.md entry, shared skills, matching discovery links, evidence-backed experts. Remove unused collection installers/metadata alongside their skills.
- Run applicable Makefile checks: `make verify` is the fast gate; `make verify-full` adds native/race/fuzz/book/distribution checks. Native input moves need `make dist-check` with copied binary, empty caches, no host Go/downloads.
- Report concrete check/publication evidence and limitations. Use [manuscript-change](../manuscript-change/SKILL.md#record-durable-lessons) for durable lessons, distinguishing current decisions from historical outcomes.
