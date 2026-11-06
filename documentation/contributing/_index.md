+++
title = "Contributing"
weight = 6

[_build]
render = "never"
list = "never"

[cascade._build]
render = "never"
list = "never"
+++

# Contributing

Build a local compiler with the [Rust toolchain guide](rust-toolchain.md#build-and-run), run the hello example, then choose the part you want to change. The [repository architecture](architecture.md#make-a-change-where-its-behavior-lives) maps each change to its implementation and tests; the [development workflow](development.md) explains the checks and book preview.

- [Compiler internals](compiler/_index.md) explain parsing, checking, and lowering.
- [Typed runtime conventions](runtime-conventions.md) describe the native runtime contract and how native operations are written.
- [Compiler conformance](compiler/conformance/_index.md) explains the semantic test plan.
- [Rust toolchain](rust-toolchain.md) covers building the Rust `ms`, its checks and crates, and its platform behavior.
- [Maintenance and compatibility](maintenance.md) cover pins, licenses, releases, and public contract changes.

Read the repository's [AGENTS.md](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md) before changing language semantics or tooling. It routes to current rules and remembered failure modes.
