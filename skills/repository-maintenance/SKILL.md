---
name: repository-maintenance
description: Organize or maintain Manuscript packages, shared guidance, embedded inputs, tool/version pins, CI, licenses, and standalone releases.
---

# Repository maintenance

Use for cleanup, package moves, pins (`rust-toolchain.toml`, `Cargo.lock`, `scripts/devtools.env`, `.node-version`, `.msversion`), CI/releases, or the skill catalog. Read [architecture](../../documentation/contributing/architecture.md), [maintenance](../../documentation/contributing/maintenance.md), and [lessons](../../.experts/repository.md).

- Simplify duplicated traversal, queries, serialization, forwarding, and CLI paths as well as layout. Name the work removed; add a layer only for a concrete contract.
- Respect crate ownership and dependency edges (see [architecture](../../documentation/contributing/architecture.md)) and the `make repo-check` invariants (`crates/ms-repo-check`).
- Moves update crate manifests, `ms-native` embed inputs, release filters, docs, and tests.
- Use pinned `rust-toolchain.toml`, `.node-version`, tool manifests, and Makefile commands. Standalone behavior cannot rely on host tools. Publish caches only after complete archive validation, with no partial ready state.
- After third-party changes run `make licenses` and `make licenses-check`. Update generated outputs through their owner.
- Keep guides/site inputs separate from ignored books, caches, SDKs, coverage, and releases; do not restore tracked generated website HTML.
- Catalog edits follow [skill maintenance](../README.md#maintain-the-catalog): one AGENTS.md entry, shared skills, matching discovery links, evidence-backed experts. Remove unused collection installers/metadata alongside their skills.
- Each CI job pays setup, so prefer few balanced jobs, but keep packaging as parallel jobs (a combined job was slower on 4-core runners). Every PR enables squash auto-merge; do not hold work for owner review.
- `bench/perf/` is the performance benchmark (stdlib ns/op and pure-Manuscript programs against other implementations); never mix its results with agent-bench. `bench/agent/` is the agent benchmark: it measures how well agents solve the same challenges in TypeScript, Go, Rust, and Manuscript (hidden tests, tokens, turns, time, cost). Keep its transcripts out of git; see its README.
- `rust-toolchain.toml` pins the compiler; CI runs fmt and clippy, nextest (two partitions), and the corpus (four shards), skipped for documentation-only changes; `.github/workflows/rust-dist.yml` packages the six targets with `scripts/package-rust.sh` and `release.yml` publishes them. `Cargo.lock` is committed and builds use `--locked`. See [Rust toolchain](../../documentation/contributing/rust-toolchain.md).
- Run applicable Makefile checks: `make verify` is the fast gate; `make verify-full` adds the conformance corpus, book, and distribution checks. Native input moves need `make dist-check`.
- Report concrete check/publication evidence and limitations. Use [manuscript-change](../manuscript-change/SKILL.md#record-durable-lessons) for durable lessons, distinguishing current decisions from historical outcomes.
