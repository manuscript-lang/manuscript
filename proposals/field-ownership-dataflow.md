# Field-level ownership dataflow

## Summary

- Problem: ownership is tracked per binding, not per field. A field of an owned record cannot be moved out, so code clones it (`return b.items.clone()`), and four separate facts (`drops_old`, `close_moves`, `moved_payloads`, `implicit_closes`) each approximate one slice of "what is still initialized here".
- Change: one forward dataflow over field paths (`Place`, `ownership/places.rs`) computes initialized, moved and re-initialized state at every point. Diagnostics and lowering's cleanup both read its result. It replaces the four facts above rather than running beside them.
- New behavior it enables: `let x = b.f`, `return b.f` and passing `b.f` to a consuming parameter move the field when `b` is an owned local or parameter and the use is the field's last. The other fields keep their exact cleanup.
- Gate: a counting harness lands first (results, cleanup order and count, clones, allocations, copied bytes; Debug and Release). No stage may raise a count without a stated reason.
- Cost: static analysis only. No syntax change. No runtime representation change in this stage (drop flags per moved field path already exist as `drop.if`).
- Evidence of benefit is modest today: of 224 `.clone()` calls in `stdlib/`, none clones a field of an owned local or parameter at its last use (the field clones are `self.failure` in `io.ms:130`, `self.middleware` in `router.ms:216` and `entry.key` in `sorted.ms:352-387`, all of borrowed or `self` storage, which stay clones). The win is user-code ergonomics and a sound fact for stage 6; the harness measures it on fixtures, not on stdlib.
- Decisions requested (user-visible): (1) accept partial moves out of owned records at all, reversing the 2026-10-26 choice in [move-out-of-places](move-out-of-places.md) ("the checker needs no hole or partial-move tracking"), which chose list-only primitives because general holes were judged too costly; Chinmay's roadmap item 1 asks for this, and the harness is the evidence gate. (2) A partial move out of a parameter makes that parameter `Consume`, which breaks callers that reuse the argument.

## Status

Proposal, 2026-10-30, against `origin/main` at `083edc8e`. Stage 4 of [solid-value-semantics](solid-value-semantics.md). Direction (Chinmay): "Track ownership per field, through every control-flow path ... Use one shared dataflow analysis for those facts. It should drive both diagnostics and cleanup generation." Order: "fix the known holes → unify field-level ownership dataflow → define mutation and cleanup contracts → use those facts for copy/allocation elimination."

## Problem

Verified on `083edc8e` with `ms check`:

```manuscript
type Big:
    name: String
    items: List[Int]

fn take(b: Big) List[Int]:
    let xs = b.items
    return xs
```

- Rejected: `cannot move `xs` out: it only borrows its value (a borrow); use `xs.clone()` to get an owned copy`. `let xs = b.items` is a shared borrow even though `b` is owned and dead afterwards.
- `fn items_of(b: Big) List[Int]: return b.items` is rejected too: "returns part of a parameter ... write `ref` ... or return an owned copy with `.clone()`". The owned parameter is consumed by the caller, yet the only escape is a deep copy of `items`.
- Both `let xs = b.items` and `let n = b.name` followed by use of each is accepted today, as borrows.
- `var b = Big(..); if c: b.items = [4]` is accepted; `Access::Write` plus `drops_old` handle whole-binding reassign, and field assignment drops the old part in lowering (`close_discarded`). Nothing models "this field was moved, this one was not".

Where state is derived today:

| Fact | Where | Granularity |
| --- | --- | --- |
| `Access::Move` per use | `ownership/walk.rs`, backward liveness (`live.rs`) | whole binding |
| `drops_old` | set at `walk.rs:1826` | whole-binding assignment only |
| `implicit_closes`, `close_moves` | produced in `walk.rs` (`unclosed_resources`, `consumed_param_resources`); consumed by `ms-lower` `close.rs` (flag at 254, `capture_closer`, `moved_closer`), `func.rs:1001`, `stmt.rs`, and by `ms-tooling` (`lint/flush.rs`, `collect.rs:118`) | whole Resource-class binding |
| `moved_payloads`, `consumed_scrutinees` | per-uid set from `arm_payloads` (`walk.rs`); read at `matching.rs:83` | payload binding |
| MIR verifier move/maybe-moved dataflow | `ms-mir/src/verify.rs` | SSA value |

A field path appears only in `Place` for overlap checks (`places.rs`), never as ownership state.

### Non-goals

- Element-level moves out of collections (`xs[i]` stays a borrow; `List.replace`/`swap` from [move-out-of-places](move-out-of-places.md) cover it).
- Moving out of a type that has its own `Closeable.close`, or out of a borrow, `ref` field, carrier, closure capture or `var` borrow: still rejected.
- Mutation-overlap, cleanup-timing and clone contracts (stage 5) and allocation elimination (stage 6).

## Revision after step 3 (2026-10-30): lowering keeps copying

Implementing the checker showed that cleanup needs no new per-field flags to be sound. A consumed projection already lowers as a borrowed leaf plus `Copy` (`FnLower::owned`), and the rest of the record is dropped whole at scope exit, so accepting the move in the checker cannot double free. Per-place liveness (`Liveness.places`, `live.rs`) replaces the forward moved/maybe state: a move is legal at its last use, which already covers branches, loops, early exits and re-initialization, and a later use of an overlapping place is reported as `moved here but used again`. What the earlier design called per-field drop flags becomes an optimizer job: the copies thread's `rec.release` and the `copyelim` rewrite turn `rec.get; copy; drop` into a move plus a release of the other leaves, and `make count-check` shows when the copy disappears. The `PathFacts` table, `exit_state` and `flags` below are therefore not built unless the optimizer cannot cover a shape. `Facts.partial_moves` records the accepted moves. Receivers (`self`) are excluded from the first cut, and `let x = b.items` stays a borrow.

## Design

**Rule:** a *tracked place* is a binding plus a path of `Field` steps (`b`, `b.items`, `b.a.c`). `Element` steps are never tracked; a move through one is rejected as today. Every tracked place is in one of three states at each program point: **init**, **moved**, or **maybe** (moved on some paths). One analysis computes the state; everything else reads it.

### Analysis

- Forward, per callable, over the same statement structure `walk.rs` already traverses. Branch join: equal states stay, unequal become **maybe**. Loop: iterate the head state to a fixpoint (monotone: init ≤ maybe ≥ moved, so it terminates). `return`, `break`, `continue` and `try` exits carry the state at that point to their target; this is the "early return" case.
- Events on a place `p` rooted at an owned binding:
  - consuming use of `p` (initializer of `let`/`var`, `return`, consuming argument, record/list/map element, escaping capture) at its last use: `p` becomes moved. Not last use: stays a borrow, exactly as today.
  - assignment `p = v`: evaluate `v`, then re-initialize `p`; the old value is dropped only if `p` was init, or conditionally if maybe (the rule `drops_old` approximates).
  - read or borrow of `p` or any prefix or extension of it while `p` is moved or maybe: error `use of moved field`. Reading a sibling field is fine. Using the whole binding (`b`, `b.clone()`, passing `b`) while any field below it is moved or maybe is an error naming the field.
  - assigning a whole binding re-initializes all of its places.
- Rejections: moving a field out of a type with its own `Closeable.close` (the close would see a hole); out of a `ref`/carrier field; out of a binding that is itself a borrow; through `Element`. Diagnostics keep today's remedy text (`.clone()`).

### Output consumed by lowering

```text
PathFacts (per callable):
  moves:      NodeId -> Place          # the use that moves a place
  exit_state: (ScopeExit) -> [(Place, Init|Moved|Maybe)]   # per binding at each scope exit
  flags:      Place -> FlagId          # only for places that are Maybe at some exit
  reinit:     NodeId -> Place          # assignment that re-initializes a moved place
```

- `close.rs` closes/drops a binding at scope exit as: whole binding if all places init; otherwise per-field glue for init fields, skip moved fields, test the flag for maybe fields. A binding with no moved field generates exactly today's code.
- Drop flags reuse `drop.if` (`ir.rs` header) and the `flag` plumbing at `close.rs:254-270`, generalized from per-binding to per-place.
- The checker's rejection and the lowering plan come from the same table, so they cannot disagree (the failure mode of P2/P4 in the parent proposal).

### Replaces

Honest scope: the four facts are not four views of one event. `implicit_closes`/`close_moves` apply only to Resource-class bindings and closable parameters, `drops_old` to any whole-binding write, `moved_payloads` to match arms. The analysis folds in what is the same event on a place, and each PR must show it:

- `drops_old`: a `Write` event on a whole-binding place. Folds in.
- `close_moves`: a move event on a Resource binding place, keyed by the moving `NodeId` (already what `PathFacts.moves` carries; closure-capture moves, `capture_closer`, are an event kind). Folds in only if the old and new sets are identical on the corpus (the step 4 bar).
- `moved_payloads`: a payload is not a path under the scrutinee (it is a binding per arm). It stays, reading the same table, unless step 4 shows a simpler form. Not claimed as removed.
- Tooling consumers (`lint/flush.rs`, `inspect` `collect.rs`) move to the new table in their own step.

Cleanup-stack registration (`CleanupPush`, `unwind.rs`) for faults and cancellation must unregister per moved field, not per binding; step 4 designs this against the existing `entry_of`/`msrt_cleanup_discard` path.

### Liveness is per place

"Last use" is a backward fact. `live.rs` computes it per binding. For a field move, liveness is extended to places: a use of `b.name` is not a use of `b.items`; a use of `b` (whole) is a use of every place under it; a use of `b.items.x` is a use of `b.items`. A move of `p` is legal when no later use reads `p`, a prefix of `p`, or an extension of `p` without an intervening re-initialization. The forward state above then checks the moves and the join states.

### What lowering does with a partly moved record

MIR already flattens records to leaves with `rec.get`, `move.out` and `drop.if` (`ir.rs` header). A move of `b.items` is `rec.get` plus `move.out` of that leaf. Scope exit drops the other leaves individually (the same per-leaf glue `close_with_parts` generates for a record, minus the moved leaf), and `drop.if` guards a leaf that is maybe-moved. No new MIR ops are expected; if the verifier cannot express "record minus one leaf", step 4 adds the smallest op and says so in the PR.

### Soundness cases (each is a fixture)

- Loop moves `b.items` with no re-initialization before the back edge: rejected "moved in a previous iteration".
- Closure: a non-escaping closure that reads `b.items` borrows it; an escaping capture of `b.items` at last use moves that place; capturing `b` whole while a field is moved or maybe is rejected.
- `try`/early return/`break`: each exit carries its own state; error paths drop exactly the initialized leaves; a fault or cancel unwinds only unmoved leaves.
- `match b` and `b.clone()` after `let xs = b.items`: rejected; `match b.name` accepted; a payload pattern over a moved alternative field rejected.
- Reassign: `b.items = v` re-initializes only when `b` is `var`; moving a field out of a `let` or a non-`var` parameter and reassigning is rejected.
- `Copy`-class fields (`Int`, records of scalars) never move; `let n = b.count` does not change state.
- Generic `T` field: class is decided on the checked type (`Move`, as today); a `T: Closeable` field behaves as a Resource field and is outside the first cut (see Open questions).
- A live shared borrow of `b.items` followed by a move of it is rejected by the existing lexical-borrow rules; a `ref` result derived from `b.name` keeps `b.name` initialized.
- Through `Element`: never tracked; moves rejected as today.
- Types with their own `Closeable.close`, and Resource-holding records (closer order is fixed by [close-owned-parts](close-owned-parts.md): own `close`, then fields last-declared first): first cut rejects all field moves out of Resource-class records.

### Examples (after the stage)

```manuscript
type Big:
    name: String
    items: List[Int]

fn take(b: Big) List[Int]:      # accepted: moves b.items; b.name is dropped at return
    return b.items

fn both(b: Big) Int:
    let xs = b.items            # moves items
    return xs.length() + b.name.length()   # accepted: name is still init

fn bad(b: Big) Int:
    let xs = b.items
    return b.items.length()     # rejected: use of moved field `b.items`
```

Branches: `if c: let xs = b.items` leaves `b.items` **maybe**; any later read of `b.items` or of `b` is rejected, and scope exit drops `items` under a flag.

## Counting harness (lands first)

- Programs: `tests/ownership-counts/*.ms`, small. Counters are read like `scripts/leak-check.sh` does: a runtime built with `ms-rt/stats` prints them to stderr at exit and a script (`scripts/count-check.sh`, `make count-check`) compares them with a `# expect-counts:` header. `# expect-mir:` is a compile-time text match with no execution, so this is a new convention, not the same one.
- Counters: the `stats` feature already counts allocations and live blocks (`alloc.rs`). Clone-helper calls and bytes copied by clone/copy glue are new runtime work in step 1, counted in the glue helpers, not by allocation. Cleanup order and count are program-visible: each fixture's resource types print on `close`, and the fixture asserts the printed sequence.
- Run twice: Debug (Cranelift) and Release (LLVM where the platform ships it).
- Coverage: nested wrappers, captures, generic calls, partial moves, failure paths (`try` exit and fault between initialization steps), loops with conditional moves.
- Rule: a change may not raise any count without a one-line reason in the PR. Expectations are per backend (`debug:` and `release:` lines), because LLVM and the MIR `opt` passes legitimately change allocation counts; clone-helper calls and cleanup order are expected identical across backends. A count change caused by an unrelated optimizer PR updates its expectation with a reason.
- CI: runs on the jobs that already run `make leak-check` (Linux, macOS, Windows gnullvm); no platform is skipped.
- First PR records today's counts for the current clone-then-return idioms, so the stage's win (clone count and bytes copied dropping to zero for `take`) is measured, not asserted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` (`stats`) | clone and bytes-copied counters | counting harness |
| `crates/ms-check/src/ownership` | new `paths.rs` forward analysis; `live.rs` liveness per place; `walk.rs` emits events; `places.rs` reused; `drops_old` removed, `close_moves`/`implicit_closes` folded if identical | ownership.rs unit tests, conformance accept/reject cases for each event, branch, loop, early return, reinit |
| `crates/ms-check/OWNERSHIP.md` | rule text for partial moves (rule lands before the code) | repo-check |
| `crates/ms-lower` (`close.rs`, `stmt.rs`, `scope.rs`) | per-place close/drop and flags from `PathFacts` | `# expect-mir:` fixtures, e2e, counting harness |
| `crates/ms-mir/src/verify.rs` | per-path moved-field check | verifier unit tests on hand-written MIR |
| `crates/ms-tooling` (`lint/flush.rs`, `collect.rs`) | read the new table instead of `close_moves`/`implicit_closes` | lint and inspect tests |
| `crates/ms-mir/src/opt` | unchanged (`lastuse` already treats drops as movable; verify it keeps field drops after moves in the harness) | harness |
| parser, formatter, lint, LSP | unchanged (no syntax) | LSP diagnostic text covered by conformance |
| `stdlib/*.ms` | convert `.clone()`-to-return idioms found by `ms search_symbol`/grep; no new API | `bench/perf` rerun, dated section |
| documentation | ownership guide: moving a field out of an owned record | `make docs-check` |

## Alternatives

| Option | Verdict |
| --- | --- |
| Do nothing | Keeps whole-record clones for field extraction and four overlapping approximations; stage 6 (move dead inputs into results) has no sound fact to build on. Rejected. |
| Whole-binding moves only, plus a `take`/`replace` primitive per field | Already exists for lists/Optionals ([move-out-of-places](move-out-of-places.md)); does not give `return b.items` and leaves drop-state split across facts. Insufficient alone, still useful. |
| Runtime-only: per-field drop flags set by lowering, no checker facts | Cleanup would be right but use-after-move stays undiagnosed, and checker and lowering would again derive state separately. Rejected. |
| Dataflow in MIR only (verifier infers) | MIR has no source names for diagnostics, and checking after lowering reports errors in generated code. Rejected; MIR keeps a verifier check only. |
| Copy-on-write fields | Out of scope per the parent proposal's non-goals. |

Drawbacks: a new analysis in a 3.2k-line `walk.rs`; maybe-moved fields add flags (only where a path actually moves a field conditionally). Disjoint-field and loop cases need careful fixtures.

## Staging and verification

1. **Harness PR**: runtime counters, `make count-check`, fixtures recording today's behavior (including the clone-then-return idioms). Gate: CI green on three platforms, counts committed.
2. **Rule text PR**: OWNERSHIP.md partial-move rules, diagnostic sub-code entry, fixture list. Needs the two decisions above answered.
3. **Per-place liveness and analysis PR**: `live.rs` extension and `paths.rs` compute facts; lowering still uses the old facts. Gate: zero new diagnostics across the whole conformance corpus, e2e fixtures and `stdlib/`; identical MIR on the corpus.
4. **Lowering PR(s)**: per-leaf drop and flags from `PathFacts`; `drops_old` removed; `close_moves`/`implicit_closes` replaced only if the old and new sets are identical on the corpus; cleanup-stack unregistration per leaf. Gate: harness counts unchanged or lower, `make verify-full`, `make leak-check`.
5. **Tooling PR**: lint and inspect read the new table.
6. **Verifier PR**: per-path moved-field check on lowering output.
7. **Adoption PR**: new accept fixtures drop clone count and bytes copied to zero for the `take` shapes; docs; `bench/perf` unaffected is recorded.

Go/no-go: stop after step 3 and keep today's behavior if the analysis reports any new diagnostic on existing code or needs a per-feature exception; stop after step 4 if the folded sets are not identical and cannot be reconciled in one PR.

## Open questions

- Resources: should a plain record that holds a `Resource` field allow moving that field out (the record has no own `close`)? Recommend yes in step 4 once the harness shows close order is preserved; start with `Move`-class fields only.
- Partial move of a *parameter* changes the callee's mode from `Borrow` to `Consume` for that parameter (found by the existing fixpoint, as for payload moves; place-level events must keep it terminating, shown in step 3). Callers that reuse the argument start failing. Recommend accepting: it is the rule that `return b.items` consumes `b`, and the diagnostic suggests `.clone()` at the caller.
- Resource-holding records: allow field moves once close order is preserved in the harness? Recommend a later proposal.
