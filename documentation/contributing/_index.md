+++
title = "Contributing"
weight = 6
+++

# Contributing

Start with the [repository architecture](architecture.md), then use the [development workflow](development.md) to build, test, and publish documentation.

- [Compiler internals](compiler/_index.md) explain parsing, checking, and lowering.
- [Go representation](go-lowering-representation.md) states when a type lowers to a Go reference or a value.
- [Go lowering units](go-lowering-units.md) explain how lowering splits into independent, parallel units.
- [Typed runtime conventions](runtime-conventions.md) describe the generated runtime contract and how native operations are written.
- [Compiler conformance](compiler/conformance/_index.md) explains the semantic test plan.
- [Rust toolchain](rust-toolchain.md) covers building the Rust `ms`, its checks and crates, and how it differs from the Go `ms` before cutover.
- [Maintenance and compatibility](maintenance.md) cover pins, licenses, releases, and public contract changes.

Read the repository's [AGENTS.md](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md) before changing language semantics or tooling. It routes to current rules and remembered failure modes.
