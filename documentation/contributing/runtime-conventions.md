+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

Locate authoritative layouts to catch duplicated ABI assumptions in agent-written native code (repository root).

```sh
rg '^pub struct (Obj|StrVal|TypeDesc)' crates/ms-rt-abi/src/lib.rs
```

```text
pub struct Obj {
pub struct StrVal {
pub struct TypeDesc {
```

- These are Rust declarations; alpha layouts may change.
- Use shared layouts rather than duplicated offsets.

<span id="host-escalation"></span>
<span id="naming-and-shape"></span>
<span id="representation"></span>
<span id="the-contract-comes-from-declarations"></span>
<span id="verifying"></span>

Next: [runtime ABI](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt/ABI.md), [cleanup](../core-language/cleanup/_index.md), and [host cancellation](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-rt/src/start.rs).
