# Contracts, effects and refinement types

## Summary

- Problem: a reviewer must read every body to know what a function needs, promises, or touches, and agent-written code gets bounds, validation, and authority wrong with no compiler signal.
- Change: three additive features that put intent in signatures: `requires`/`ensures`/`invariant` clauses, `uses` effect sets, and `where`-refined types.
- One shared predicate language (decidable: comparisons, boolean logic, `len`, field access, bounded quantifiers) and one small checker-side prover serve all three; unproven obligations become runtime checks and generated property tests, never silent passes.
- Cost: new syntax in three places, a prover in `ms-check`, lowering of checks; every feature is opt-in and zero-cost for programs that do not use it.
- Decision requested: approve stages 1 and 2 (effects). Contracts and refinements (stages 3 to 6) are gated on a spike report; no syntax for them lands before it. Skeptical review of 2026-10-28 is recorded in [Review outcome](#review-outcome).

## Status

- Proposal, 2026-10-28, checked against main at `5664578e`.
- Direction (Chinmay, 2026-10-28): items 1 to 3 of the agent-correctness list: compiler-checked contracts (static where possible, else generated property tests), effects and capabilities in signatures, refinement types. "This is some of the policy work we started was going, let's continue on that."
- Builds on earlier work (project files, written against the removed Go tree; Rust equivalents verified below):
  - `proposals/capabilities-enforcement.md`: authority categories from `bindings.json`, `ms inspect --authority`, `[permissions]` in `ms.toml`, attenuated views, OS sandbox.
  - `proposals/capabilities-os-mechanisms.md`: Landlock, seccomp, Seatbelt, Windows mechanisms for the process-level layer.
  - `proposals-drafts/policy-end-to-end.md`: `action`/`policy` declarations, decidable rule language, `ms policy check`, fuzzing.
- Supersedes: `.experts/language.md` "Parameterless main and imported host accessors" and `skills/language-design-taste` line "Do not impose per-function authority declarations or manifest permission enforcement without a new user direction". The 2026-10-28 direction is that new direction; both entries must be updated in the first PR that adds a declaration.
- Kept: parameterless `main`, imported accessors, ordinary service parameters.
- Name clash: the language already uses "contract" for interfaces (`documentation/core-language/types/contracts.md`). This proposal says "contract" only in prose for `requires`/`ensures`; no `contract` keyword.

## Problem

- Authority is ambient: any module can import `fs`, `net`, `process` accessors; a signature never shows it (verified: `stdlib/net.ms`, `stdlib/fs.ms`, `stdlib/process.ms`). Only `Network.restrict` narrows anything today (`stdlib/net.ms:268-303`; policy in `crates/ms-std-net/src/policy.rs`).
- Preconditions live in prose comments. `values[index]` faults out of range (`documentation/core-language/types/collections.md`), so an agent that forgets a bound ships a runtime fault.
- Validation types (`Email`, port, non-empty list) are plain `String`/`Int`/`List`; nothing forces a check before use.
- Non-goals: full deductive verification, SMT dependency in stage 1, OS sandboxing (stays in the capabilities proposal), a `fault` effect (see Open questions), changing `main` or accessors.

## Design

### Predicate language (shared)

- A predicate is an ordinary `Bool` expression restricted to: `Int`/`Float`/`String`/`Bool` literals, parameter and field reads, `== != < <= > >=`, `and or not`, `len`, `in` a range, `is_empty`, and `all`/`any` over a collection with a lambda whose body is a predicate. Calls only to `pure` functions (stage 4 rule), no mutation, no loops.
- It lowers to ordinary Manuscript, so the runtime evaluator is the language itself. Rust adds no evaluator.
- `old(expr)` is allowed only in `ensures` and reads the pre-call value of a parameter.

### 1. Contracts

```text
# Language change; does not check today.
def at(items: List[Int], index: Int) -> Int
    requires 0 <= index < len(items)
    ensures result == items[index]:
    return items[index]
```

- `requires`: caller obligation. At each call site the prover tries to discharge it from facts in scope (literals, enclosing `if` conditions, earlier `requires`, refined parameter types). Proven: no code. Unproven: a compile warning by default (error under `ms check --strict-contracts`) and a runtime check before the call that faults with the predicate text and argument values.
- `ensures`: callee promise, checked at every `return` in builds with checks on; exempt from proof in stage 1 (see Staging). `ms test` derives property tests from it.
- `invariant` on a `type`: checked after construction and after each `var def` method returns. The set of fields it may read is that type's own.
- Checks default on in debug and `ms test`, off in release unless the manifest says `[checks] contracts = "always"`. A proven obligation is never emitted in either mode.
- Interfaces: an operation may carry `requires`/`ensures`; an implementation may weaken `requires` and strengthen `ensures` only, checked by implication in the prover; anything it cannot prove is an error.
- Generated tests: `ms test` finds functions with `requires`/`ensures`, builds generators from parameter types plus refinements (stdlib `@std/test`), keeps inputs satisfying `requires`, and asserts `ensures` and type invariants. Failures print a minimal shrunk input and the clause. The generator and shrinker live in `stdlib/test/*.ms`; Rust only exposes the list of annotated functions.

### 2. Effects

```text
# Language change; does not check today.
def fetch_title(net: Network, url: String) -> Result[String, HttpError] uses net.connect:
    ...
```

- Effect names are the authority categories already designed: `fs.read`, `fs.write`, `net.connect`, `net.listen`, `net.resolve`, `exec`, `env.read`, `env.write`, `process.control`, `system`, `terminal`. Source of truth is a new `authority` field per entry in `stdlib/bindings.json`, so stdlib stays declarative.
- Inference: the checker computes each function's effect set bottom-up over the call graph (calls to bindings contribute their category; calls through interface views contribute the declared `uses` of the operation; closures contribute to the enclosing function when called, to their own type when passed). Cycles take the fixed point.
- Rule: if a function has a `uses` clause, inferred must be a subset of declared; otherwise compile error naming the offending call. No clause means inferred and unchecked, so existing code is unaffected.
- `uses` with an empty list means pure: `uses`. Interface operations may declare `uses`; implementations must stay within it.
- Review: `ms inspect --effects [--json]` prints per-function sets; `ms review` reports changed sets on exported functions ("`fetch_title` newly uses `exec`"). A manifest option `[effects] require = "exported"` makes a missing clause on an exported function an error, which is the reviewer-reads-signatures mode.
- Package ceiling: `[permissions]` from the capabilities proposal bounds the union of a package's effects at check time; enforcement by attenuated views stays that proposal's Layer 2 and is not repeated here.
- Capabilities stay ordinary values (`Network`, `FileSystem`). `uses` states what a function does; the parameter states what it may do it with. Both are needed: a `uses net.connect` function with no `Network` parameter still reached the ambient accessor, and effects make that visible.

### 3. Refinement types

```text
# Language change; does not check today.
type Port = Int where value >= 1 and value <= 65535
type NonEmpty[T] = List[T] where len(value) > 0

def listen(port: Port) -> Unit:
    ...

listen(8080)         # proven from the literal
listen(read_port())  # error: Int is not Port; use Port.check(value)
```

- A refined type is a distinct nominal type with an underlying type and a predicate over `value`. It converts to the underlying type implicitly; the other direction needs proof or an explicit check.
- Introduction: (a) a literal or constant the prover evaluates; (b) `Port.check(value) -> Optional[Port]`, generated, the single runtime conversion; (c) flow narrowing inside `if value >= 1 and value <= 65535:` where the prover derives the predicate.
- Elimination is free: a `Port` is an `Int` wherever an `Int` is expected, and contributes its predicate as a fact (so `at(items, i)` with `i: Index` proves `requires 0 <= i`).
- Refined results can name relations to inputs: `-> Int where value < len(items)`.
- Mutation: refinements on `var` places hold only until the next assignment; assignment must re-establish the predicate or is a compile error.

### Prover (stage 1 shape)

- In `ms-check`, linear integer arithmetic over `Int` locals with interval and equality propagation, plus `len` facts, plus boolean structure. Sound, incomplete: "cannot prove" is the only failure and always falls back to a runtime check, never to acceptance.
- No external solver dependency. An SMT backend is an optional later stage behind the same interface, only if measured proof rate on real code justifies it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | `requires`/`ensures`/`invariant`/`uses` clauses, `where` on `type`; contextual keywords | parser accept/reject fixtures |
| `crates/ms-check` | predicate checker, prover, effect inference, refinement conversions, diagnostics with a corrected example | `tests/conformance` reject cases with exact messages |
| `crates/ms-lower` | emit entry/exit checks for unproven obligations, `Type.check` | e2e fixtures run with checks on and off |
| `crates/ms-rt`, ABI | unchanged (checks are ordinary code and a fault with a message) | e2e |
| `stdlib/bindings.json` | `authority` field per entry | audit test that every host-reaching binding is tagged |
| `stdlib/test/*.ms` | generators, shrinking, contract-test driver | `ms test` fixtures |
| formatter, lint, LSP, VS Code | clause layout, hover shows effects and refinements, unproven-obligation lint | formatter round-trip, LSP tests |
| CLI | `ms inspect --effects`, `ms review` effect diff, `ms check --strict-contracts` | CLI tests |
| manifest (`ms-project`) | optional `[checks]`, `[effects]`, later `[permissions]` | manifest tests |
| `documentation/core-language` | new pages `functions/contracts.md`, `functions/effects.md`, `types/refinements.md`; update `.experts/language.md` and taste skill | `make docs`, repo-check |
| Platform parity | pure compiler and `.ms` logic; no OS-specific code, so all tests run on Linux, macOS, Windows | CI matrix, nothing gated |

## Alternatives

- Do nothing: reviewers keep reading bodies; the agent-error classes above stay runtime faults. This is the baseline the evidence plan below must beat.
- Comments and naming conventions: not checked, so not usable by an agent loop.
- Package-level authority only (capabilities proposal Layer 1): cheap and already designed, kept as the first stage, but gives no per-function review and no way for an agent to state intent.
- Full SMT verification from day one: heavy dependency and cross-platform build risk; incomplete provers with runtime fallback capture most value first.
- Types only (no contracts): refinements cover value shape but not relations between arguments and results.
- Drawbacks: three syntax additions; a prover can reject nothing but can mislead if a user reads "no warning" as "proven" (so diagnostics distinguish proven, checked at runtime, and unchecked); `uses` clauses can go stale only in the safe direction (inferred must fit).

## Staging and verification

Each stage lands green on all platforms and is independently useful.

1. Effects, read-only: `authority` in `bindings.json`, inference, `ms inspect --effects`, `ms review` diff. Gate: audit finds no untagged host-reaching binding; inference over `stdlib/` and `tests/` agrees with hand-checked samples.
2. `uses` clause: syntax, subset check, interface operations, manifest `require`. Gate: reject fixtures; unannotated programs unchanged (full conformance corpus).
3. Spike, no syntax (gates everything below). Deliverables, in a report under `bench/` or `proposals/`:
   - Proof rate: hand-annotate about 30 real call sites from `stdlib/*.ms` and `tests/e2e` (loop indices, `len(x) - 1`, call results, field paths) and count obligations a linear-arithmetic prover discharges versus falls to runtime.
   - Do-nothing evidence: list failures in `bench/agent/` runs that a `requires` or refinement would have caught at compile time.
   - Seeded-bug test: an off-by-one in a fixture, found by a prototype generated test.
   - Comparison: a stdlib validating type (`Port.check`) written in plain `.ms` versus the `where` form, to show what syntax adds.
   Go/no-go: stop contracts and refinements if proof rate is low or plain stdlib types give the same checks.
4. Only if the spike passes: `requires` with runtime checks, then call-site proof, then refinements, then `ensures`/`invariant` and `ms test` generation, each as its own proposal-reviewed PR.
5. Optional: SMT backend, `[permissions]` enforcement, OS layer, per the capabilities proposals.

## Review outcome

Skeptical review, 2026-10-28. Accepted: effects stand; stages 3 to 5 lacked evidence, now the spike above. Rules adopted for stage 4, to be specified in its own proposal before syntax:

- Soundness: `ensures` also runs on `try`/`?` exits; on a fault no `ensures` is claimed. `old()` is allowed only on parameters copied by value, not on moved or mutated owned parameters.
- Refinements apply to immutable `let` bindings and parameters first. A refined `var` place, a captured mutable binding, a lent view, or a collection element (`List[NonEmpty]`) carries no fact once any mutation is possible, so the prover drops it rather than trusting it.
- A failed `requires` faults before the call; owned arguments and resources are dropped by the normal fault-site cleanup (`proposals/fault-site-drops.md`). Fault messages print the predicate text and only arguments with a `Display`-style rendering.
- Modes: checks that are not proven run in every build mode unless the manifest explicitly turns them off, so behavior does not silently differ between debug and release.
- Effects: an interface operation without `uses` is inferred as unknown and requires an explicit clause under `[effects] require`; generic callables take the union of their instantiated argument effects; a `Network` parameter and `uses net.connect` are checked against each other (a `uses` category with no matching capability parameter or accessor is an error).
- Syntax: clause order is `uses`, `requires`, `ensures`; refined `self` is spelled `value` in `where`; `result` is contextual inside `ensures` only; predicates may call functions marked `pure` (empty `uses`, no mutation) so `is_valid(x)` is reusable.
- Predicate lowering shares the checker's type rules instead of a separate evaluator.

## Open questions

- Keyword spelling: `uses` for effects versus reusing `with` (taken by cleanup scopes). Recommendation: `uses`.
- Refinement syntax `type Port = Int where ...`: Manuscript's `type` declares records today (`type Pair[A, B]:`), so `=` aliases-with-predicate is a new form. Alternative: `type Port: Int where value >= 1`. Recommendation: the `=` form.
- Should `fault` be an effect? Nearly every function can fault (indexing), so a binary tag carries little; a narrower `may_fault` fed by unproven `requires` is possible later. Recommendation: defer.
- Checks in release by default off versus on. Recommendation: off, with `[checks] contracts = "always"`.
- Strict-by-default for new projects (`ms new` writes `[effects] require = "exported"`). Recommendation: yes, after stage 2.
