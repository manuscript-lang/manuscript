+++
title = "Contributing"
weight = 6
+++

# Contributing

Start with the [repository architecture](architecture.md), then use the [development workflow](development.md) to build, test, and publish documentation.

- [Compiler internals](compiler/_index.md) explain parsing, checking, and lowering.
- [Typed runtime conventions](runtime-conventions.md) describe the native runtime contract and how native operations are written.
- [Compiler conformance](compiler/conformance/_index.md) explains the semantic test plan.
- [Rust toolchain](rust-toolchain.md) covers building the Rust `ms`, its checks and crates, and its platform behavior.
- [Maintenance and compatibility](maintenance.md) cover pins, licenses, releases, and public contract changes.

Read the repository's [AGENTS.md](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md) before changing language semantics or tooling. It routes to current rules and remembered failure modes.
