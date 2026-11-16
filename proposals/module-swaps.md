# Module swaps

## Summary

- Problem: tests cannot fake the clock, files, network, environment or a project module without threading a parameter through every caller, and there is no way to run a program with less reach than the machine gives it.
- Change: one idea. A *swap* is an ordinary module whose header says which module it stands in for. When a swap is part of a program, every other import of that module gets the swap instead. Tests turn a swap on by importing it; an agent runner turns one on with `--swap`. Same file, same rule, same check.
- Decision requested: approve the directive, the two ways to turn a swap on, and the one rule (same signature, never more reach).

## Status

Proposal, 2026-11-16. The spike on this branch builds the redirect for standard and project modules, one-function swaps, `--swap` on `ms run` and `ms test`, and the signature check for standard modules. Not built: the reach rule, the signature check for project modules, tooling. Direction (Chinmay): module mocks over capability values because they are simpler; fit with effects; `vi.mock` ergonomics but checked when compiling; two uses, limiting agents and mocking in tests; more than standard modules.

## Design

**A swap says what it replaces.** One header line, in the same `// ms:` family as `effect` and `allow_effect`:

```manuscript
// ms: swap "@std/time.ms"

import Timestamp from "@std/time.ms"

export NOW_TEXT := "1970-01-02T00:00:00Z"

export fn now() Timestamp:
	return Timestamp(seconds: 86400, nanos: 0)
```

**A swap is on when it is in the program.** Nothing else turns it on.

- A test imports it. It almost always wants something from it anyway, here the expected time:

```manuscript
import (
	expect_equal from "@std/test/test.ms",

	NOW_TEXT from "./fake_clock.ms",
	NAME from "./fake_store.ms",
	banner from "./greeting.ms",
)

test "banner uses the fake clock and store":
	expect_equal(banner()?, f"hello {NAME}, it is {NOW_TEXT}")?
```

- A runner names it: `ms run main.ms --swap limits/no_files.ms`. The code being run cannot see or remove it, which is what limiting an agent needs.

Measured on this branch (`examples/mock-demo`): the test passes with `greeting.ms` unchanged and no `name.txt`; `ms run run_main.ms` reads the real file; with `--swap limits/no_files.ms` the same program gets `EACCES` from every file read.

**One rule for what a swap may be.**

- Names it exports replace the original's names, with the identical signature, and it uses the original's types (imports them, never redeclares them). Measured: a fake `now() Int` is now rejected: `the swap for @std/time.ms declares now as fn() Int, but the original declares fn() Timestamp`.
- Names it does not export keep the original. Swapping one function is a module with one function (`limits/no_files.ms` replaces only `read_file`; `greeting.ms` still gets the real `seconds`).
- Its body may not reach any effect the original does not declare. So a swap can change answers and take away reach, never add reach: a fake clock cannot open a socket, and a limit cannot widen what an agent may do.

**Effects stay the same story.** `ms lint` checks the program without swaps, so `MSL116` reads the same with and without them, and callers are charged the original's effects. `ms review` lists the swaps in a build next to the effects it reaches.

**Scope.**

- A swap covers the whole program, since the redirect happens once while modules load, before checking. Test files that import different swaps build as separate programs; the rest still share one.
- The swap's own imports of the original are not redirected. Standard-library code is not redirected either, so swapping `fs` does not change what another standard module reads inside the standard library.
- Methods are not swapped one by one. Swap the module, or take an interface, which already works.

**State.** Modules have no mutable state, so a swap answers from its arguments and constants: a fixed clock, a canned reply per input, a refusal. A fake that must remember (an in-memory disk with writes) still takes a capability value such as `FileTree`.

**Cost.** None when no swap is in the program. With swaps the loader reads the graph twice (swaps are only known once their file is read) and calls are ordinary direct calls, so there is no runtime cost. One extra build per distinct set of swaps in `ms test`.

**Not a sandbox.** `extern fn`, `--link` and starting a process bypass any swap. For agents it is a guard rail beside `[effects]`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-driver` `load.rs` | read `swap` headers, redirect imports, reload once with swaps known | driver unit tests; conformance fixture |
| `crates/ms-check` `checker.rs` | follow redirects for `@std/`, fall through unexported names, signature check, reach rule | reject cases with exact diagnostics |
| `crates/ms-cli` | `--swap` for `run`, `build`, `test`; one build per swap set | e2e fixture |
| `crates/ms-tooling`, `ms-lsp` | `ms review` lists swaps; hover on a swapped import | tooling tests |
| unchanged: `ms-lower`, backends | they see ordinary imports | |

## Alternatives

- Do nothing: capability parameters work today (`FileTree`, `Logger`) but add a parameter to every function between `main` and the call.
- Mapping tables (in a test header or `ms.toml`, "replace X with Y"): the first spike. Two places describe one fake, and the fake file does not say what it is. Lost on cohesion.
- Runtime patching like `vi.mock`: a lookup on every call, no inlining, nothing checked.
- Link-time symbol override: natives only, no type check, no project modules.

## Stages

1. Swap header, import and `--swap` turn-on, signature check for every module, reach rule; conformance fixtures. Gate: `make conform`.
2. One build per swap set in `ms test`; `ms review` and editor support.

## Open questions

- Should `ms.toml` be able to name swaps that are always on for a run (`[swaps] agent = [...]`)? Recommendation: not now; the runner's `--swap` covers agents and keeps one way.
