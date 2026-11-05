+++
title = "Contributing"
weight = 6
+++

# Contributing

Build a local compiler with the [Rust toolchain guide](rust-toolchain.md#build-and-run), run the hello example, then choose the part you want to change. The [repository architecture](architecture.md#make-a-change-where-its-behavior-lives) maps each change to its implementation and tests; the [development workflow](development.md) explains the checks and book preview.

- [Compiler internals](compiler/_index.md) explain parsing, checking, and lowering.
- [Typed runtime conventions](runtime-conventions.md) describe the native runtime contract and how native operations are written.
- [Compiler conformance](compiler/conformance/_index.md) explains the semantic test plan.
- [Rust toolchain](rust-toolchain.md) covers building the Rust `ms`, its checks and crates, and its platform behavior.
- [Maintenance and compatibility](maintenance.md) cover pins, licenses, releases, and public contract changes.

For a first contribution, reproduce one behavior with the compiler you just built. Find its implementation in the crate map, add or adjust a test that distinguishes the intended behavior, then make the change. Run that focused test while iterating and the applicable [check tiers](development.md#choose-checks-for-the-change) before submitting it. A documentation contribution follows the same loop: try the program or command, explain what the reader should learn, and check the rendered page.

Read the repository's [AGENTS.md](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md) before changing language semantics or tooling. It routes to current rules and remembered failure modes.
