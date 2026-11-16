# Module swaps: mocks for tests and limits for agents

## Summary

- Problem: tests cannot replace the clock, the environment, the network or a user module without passing every one as a parameter, and there is no way to run a program with less access than the machine gives it.
- Change: one mechanism. A *swap* makes every import of a module (or of single functions in it) resolve to a replacement file, chosen at build time and checked against the original signature. Tests declare swaps in a header comment; a run or build gets them from `ms.toml` or a flag, so the code under test cannot remove them.
- Decision requested: approve the mechanism, the header and manifest spellings, and the stages. No new keyword or grammar.

## Status

Proposal, 2026-11-16, checked against `main` at the commit of this branch. The spike proves the redirect for `ms test` and `ms run`; signature checking, `ms.toml`, partial swaps and the effects rules are not built. Direction (Chinmay): module mocks over capability values because they are simpler; fit with effects; ergonomics like `vi.mock` but checked at compile time; two uses, restricting agent access and mocking for tests; mock more than std modules.

## Design

A swap is `import path -> replacement file`. It is applied while the module graph loads (`ms-driver` `load.rs`), so the checker, lowering and both backends see ordinary imports of an ordinary module. There is no runtime hook and no cost when no swap is set.

**Tests** (spike, works today). A comment at the top of a test file:

```manuscript
// ms: mock "@std/time.ms" "./fake_clock.ms"
// ms: mock "@std/os/env.ms" "./fake_env.ms"

import expect_equal from "@std/test/test.ms"
import banner from "./greeting.ms"

test "banner uses the fake clock and environment":
    expect_equal(banner()?, "hello test-user, it is 1970-01-02T00:00:00Z")?
```

```manuscript
// fake_clock.ms: same name and signature as the original
import Timestamp from "@std/time.ms"

export fn now() Timestamp:
    return Timestamp(seconds: 86400, nanos: 0)
```

Measured: `ms test examples/mock-demo/greeting_test.ms` passes with `greeting.ms` unchanged. The same header in an entry file also swaps under `ms run`.

**Agent limits** (not built). The same swaps come from `ms.toml` (`[swaps]`, next to `[aliases]` and `[effects]`) or `ms run --swap FROM=TO`, and apply to every build of the program. A limit is a replacement that fails or narrows: a `net` swap whose calls return `EPERM`, or an `fs` swap that only reads under one directory. Swaps in a header comment only count under `ms test`.

**Scope.**
- A swap covers the whole program that is built, not one file. Test files with different swaps build as separate programs; files without swaps still share one.
- Only user modules are redirected. Standard-library code that calls the original inside the standard library is not, so a swap of `fs` does not change what `@std/data/config.ms` reads. The proposal lists this as a known limit.
- The replacement file's own imports are not redirected, so it can import the original for its types.

**What can be swapped.** Any module a user module imports: `@std/*` and project files. A replacement may export only some names. A name it does not export keeps the original (this is how one function is swapped). Methods are not swapped one by one; swap the module, or use an interface, which already works.

**Checking (required before merge, not in the spike).** The spike let a replacement `now() Int` through and the test printed `5`. Every exported name of a replacement must have the identical signature of the original, and types must be the original type, imported not redeclared. A mismatch is a compile error naming both signatures. This is the one place we beat `vi.mock`.

**Effects.** Lint runs on the real graph with swaps off, so `MSL116` output is the same with and without swaps. The replacement body is checked on its own `allow_effect` lines and may not reach an effect the original does not declare, so a fake clock cannot quietly open a socket. Callers are charged the original's effects.

**State.** Modules have no mutable state, so a swapped function answers from its arguments and constants: fixed clock, fixed environment, failing network, canned responses chosen by input. A fake that remembers (an in-memory disk with writes) still uses a capability value such as `FileTree`; that stays the answer for stateful fakes.

**Not a security boundary.** `extern fn`, `--link` code and starting a process bypass any swap. For agents it is a guard rail beside `[effects]`, not a sandbox.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver` `load.rs`, `project` | read swaps, redirect imports, resolve replacement paths | driver unit tests; conformance fixture |
| `crates/ms-check` `checker.rs` | follow the redirect for `@std/` imports; signature and type match; fall-through for unexported names | reject cases with exact diagnostics |
| `crates/ms-cli` | `--swap`, partition test files by swap set | e2e fixture with two files |
| `crates/ms-tooling` lint, `ms-lsp` | show active swaps; hover on a swapped import | lint and LSP tests |
| `ms.toml` parser | `[swaps]` table | manifest tests |
| unchanged: `ms-lower`, backends | they see ordinary imports | |

## Alternatives

- Do nothing: capability parameters work today (`FileTree`, `Logger`) but cost a parameter on every function between `main` and the call; Chinmay prefers swaps.
- Runtime patching like `vi.mock`: needs a table lookup per call, defeats inlining and checks nothing. Lost on cost and safety.
- Link-time symbol override: only natives, no type check, no user modules.
- A `mock fn` block inside a test: new grammar and per-test scope, which a static build cannot give. Lost on cost.
- A header comment only, no manifest: cannot serve agent limits, since the agent edits the file.

## Stages

1. Redirect plus signature checking, header form, `ms test`; conformance fixtures. Gate: `make conform`.
2. `[swaps]` and `--swap` for `run` and `build`; separate programs per swap set in `ms test`.
3. Tooling: lint, LSP, `ms review` lists swaps like effects. Bundled deny swaps if wanted.

## Open questions

- Header comment or `[swaps]` only for tests? Recommendation: both; the header keeps a test next to its fakes.
- Should unexported names fall through to the original? Recommendation: yes, so a one-function mock is one function.
- Per-test mutable state for fakes: a small runtime slot table, or keep capability values? Recommendation: keep capability values for now.
