# Solid value semantics: close the holes, then remove special cases

## Summary

- Problem: the owned-value model is right, but its rules are lost at boundaries. Accepted programs on `main` misbehave in five ways: a use-after-free through an escaping closure, a double close, two missed closes, and `let` values mutated through copies.
- Cause: the same facts are derived in more than one place, from different signals. `Classifier` walks alternative cases, but `clonable` does not. Temporary cleanup keys on `needs_drop` rather than the class. Natives default to `Copy`, and builder mutators are listed by name.
- Change: fix each hole by routing it through the existing `Classifier`, one small PR each. Then remove name-based special cases one at a time, each one an owner decision. No GC, no reference counting or copy-on-write for ordinary data, and no new framework.
- Cost: static checks only, until stage 3. Stage 3 changes user-visible APIs, and each change is gated on `bench/perf`.
- Decisions requested: D1 and D2 (stage 2), then D3 to D7 (stage 3). All of them are user-visible.

## Status

Proposal, 2026-10-30, checked against `origin/main` at `02ea1a1c`. Direction (Chinmay):
- "is our value semantics sound? feels like we're mixing value and references in weird ways"
- "i don't want special casing, we should have everything handled by language model"
- "Keep the owned-value model. Make the compiler preserve its rules consistently."
- "yeah let's make value semantics solid and performant"

This consolidates the thread's audit (`architecture/value-semantics-audit.md` in the project files) and Chinmay's independent source review of `63c8815d`.

Skeptical review (independent subagent, 2026-10-30): verdict "build with changes". It reran all nine repros. The changes it required are applied here:
- dropped the five-field obligations table and the MIR borrow and close-once checks;
- corrected P4's cause and P5's fix;
- noted that D2 depends on D1;
- listed the stage 3 API changes as decisions;
- named the real `bench/perf` suites and the `strfuse` dependency;
- removed the claim that `CallModes` needs new fields, since `retained` and `origin` already exist (`modes.rs:131-133`).

Nothing is implemented.

## Problem

Each repro below was run with `ms run` on a release build of `02ea1a1c`, and each is accepted by `ms check`. The excerpts leave out imports and helpers. The full programs are in the project files under `architecture/value-semantics-repros/`, and each stage adds them as tests.

### P1. An escaping closure keeps a view past its source (use-after-free)

```manuscript
type View:
    items: ref List[Int]

export fn main() Int:
    var xs = [1, 2, 3]
    let v = View(items: xs)
    var fs: List[fn() Int] = []
    fs.append(fn (): v.items[0] + v.items[2])
    let n = v.items.length()
    xs = [9]
    # ... allocate other lists ...
    stdout().write("n={n} closure={fs[0]()}\n").get()
    return 0
```

- Output: `closure=777`, which is freed memory reused by later lists. The closure should read 4, or the program should be rejected.
- Cause: in `lambda` (`ownership/walk.rs:2936-2944`), an escaping capture that is not at its last use takes the `shared` copy branch. A carrier is `Move` (`classify.rs:113-115`), so it is copied and never reaches `capture_move`. `capture_move` (`walk.rs:2993-2999`) already rejects `borrows(&b.ty)`, matching `OWNERSHIP.md`: a carrier "cannot be ... captured by an escaping closure".

### P2. Cloning a resource through an alternative closes it twice

```manuscript
type Holder:
    case Has(r: Res)
    case Empty

fn dup[T: Clonable](x: T) T:
    return x.clone()

export fn main() Int:
    let a = Holder.Has(Res(1))
    let _b = dup(a)
    return 0
```

- Output: `close 1` twice.
- Cause: `contracts.rs::clonable` (lines 741-748) checks `fields(t)` and a direct `closeable(t)`, but never the alternative cases. So `Holder` and `Optional[Res]` count as `Clonable`. `classify.rs::nominal` (lines 103-110) does walk the cases and returns `Resource`, so the two derivations disagree.
- `dup(some(Res(2)))` is also accepted, though it printed `close 2` only once in this run.

### P3. A resource temporary with no heap storage is never closed

```manuscript
type Res:
    id: Int

impl Closeable for Res:
    var fn close() Unit:
        stdout().write("close {self.id}\n").get()

export fn main() Int:
    let a = make(7).get_id()          # Res: Int field only
    let b = make_named("heap").get_id() # Named: String field
    return 0
```

- Output: `close heap` only. `Res(7)` is never closed.
- Cause: `FnLower::borrow` (`ms-lower/src/func.rs:550-554`) registers a temporary only when `needs_drop` holds, which is a representation fact. `close_temp` (`close.rs:165-181`) already filters on `Class::Resource`, but it never sees the value.

### P4. A generic wrapper drops its resource's cleanup

```manuscript
type Wrap[T]:
    value: T

fn keep[T](v: T) Int:
    let _w = Wrap(v)
    return 0

export fn main() Int:
    let _ = keep(Res(2))
    return 0
```

- Output: no `close 2`.
- Cause: lowering closes only bindings in the checker's `implicit_closes` (`stmt.rs:283-287`, `func.rs:986`). The checker adds a binding there only when its generic type's class is `Resource` (`walk.rs:1283`, `1463`), and `Wrap[T]` with an unconstrained `T` is `Move`.
- Lowering already has instance types (`closer_opt` substitutes, `close.rs:289`) and would close `Wrap[Res]` if the binding were listed.
- The same `shared` copy branch as P1 copies a `Wrap[T]` captured by an escaping closure. So making generic instances close (D2) without D1 would close `Res` twice.

### P5. `let` values mutated through implicit copies

```manuscript
let a = headers()
let b = a
let _ = b.append("x-k", "v")
let r = Req(a)
let s = r
let _ = s.h.append("x-j", "w")
# a.names().length() == 2
```

- `HttpHeaders` is an `extern type` with plain `fn append`. `classify.rs::native` (lines 76-78) defaults every other native to `Copy`, so `let b = a` shares the handle. `effects.rs::collection_mutation` lists mutators only for the five builders, by name, so `let` does not stop the change.
- Builders with `var`: `var b = a; b.append("x"); a.append("y")` gives `xy`, and `[a, a]` shares one buffer. A record `.clone()` keeps the builder shared (`x|0`). `build()` followed by `append` is a runtime "builder is sealed" fault.

### Not reproduced, and kept out of the design

Chinmay's source review also flags the items below. Each gets a repro before any fix (stage 2); one that does not reproduce is dropped.
- Interface values and function values may not carry consumption or cleanup obligations.
- Recursive cleanup may pick a different `close` implementation from the one visible in the source scope (`close.rs::part_closer` re-resolves by type).

### Non-goals

- Garbage collection, universal reference counts, copy-on-write collections, deep copies on capture.
- A new ownership pass, IR, per-type obligations table, or MIR borrow checker. `Classifier` (`classify.rs`) is already the shared source that `ms-lower` reads through `cx.classes`, so the fixes route through it.
- Syntax changes. `ref`, `var`, `let` and `.clone()` keep their meaning.

## Design

**The rule:** wrapping a value never changes its obligations. Whether a value can be copied, cloned or must be closed is decided by `Classifier`, which already walks fields, alternative cases and type arguments. Every other place that decides one of these asks it, instead of re-deriving.

### Stage 1: holes with no behavior decision

Each item below is a bug against the documented rules.

| Hole | Fix | Where |
| --- | --- | --- |
| P1 | Add `&& !borrows(&b.ty)` to the escaping copy condition, so a carrier reaches `capture_move` and its existing diagnostic | `walk.rs:2936-2944` |
| P2 | `clonable` returns false when `Classifier::class(t) == Resource`, which covers cases, `Optional`, `Result` and containers | `contracts.rs:715-748` |
| P3 | Register a temporary when `needs_drop` holds or its class is `Resource` | `func.rs:550-554` |
| MIR | The verifier rejects a `Copy` of a value whose type has a closer | `ms-mir/src/verify.rs` |

Expected diagnostics:
- P1 keeps the existing `capture_move` message.
- P2 is a missing-`Clonable` error at `dup(a)`.

### Stage 2: escaping captures and generic cleanup (D1, D2)

- **D1.** An escaping closure that cannot move a capture (the capture is used later, or is borrowed) is rejected, with the fix `let c = x.clone()` before the closure. This brings the code in line with `function-values-and-closures.md` ("Use `.clone()` before capturing to keep using the original") and with `OWNERSHIP.md:36` ("moved at creation"). Before landing, count the repo programs that rely on the implicit copy.
- **D2.** The checker also lists in `implicit_closes` any binding whose type mentions a type variable. Lowering then asks `cx.classes` for the instance type and emits no code when the instance has no closer.
- D2 lands only after D1. Otherwise P4's escaping copy closes the same resource twice.
- Each unreproduced item gets its repro in this stage. A reproduced one is fixed through `Classifier`; one that does not reproduce is dropped.

### Stage 3: remove special cases (D3 to D7, one PR each)

| Change | Removes | User-visible effect |
| --- | --- | --- |
| D3. `HttpHeaders` becomes an owned native: not `Copy`, dropped, cloned with the existing `msrt_http_headers_clone`, and mutators become `var fn` | P5 for headers; the native default `Copy` for this type | `var h = headers()` is needed to append |
| D4. Native default class becomes `Move` | `classify.rs:76-78` fallback | Each `extern type` declares how it is duplicated; `Duration`, `Instant` and `Timestamp` become Manuscript records over `Int` |
| D5. `ListBuilder`, `MapBuilder` and `SetBuilder` are removed in favor of `var List`, `var Map` and `var Set` | `sharedbuilder.rs` for collections; builder names in `effects.rs` | 59, 27 and 23 `.ms` files migrate |
| D6. `StringBuilder` and `BytesBuilder` become owned values with `var fn append`, and `build` consumes `self` | Builder aliasing; the "sealed" fault becomes a use-after-move error | Builders are passed with `var` |
| D7. `Shared` carve-outs (`get()` in-expression lending, `take`/`put` allowlist, worker-message name check) become guard borrows, module visibility and `Clonable` | Name checks for `Shared` | Decided in the `Lock[T]` work |

D6 performance requirements:
- `build` needs an internal, non-validating freeze native, as `msrt_strbuilder_freeze` does today (`ms-rt/src/vec.rs:1940-1952`, including the `STR_INLINE_MAX` inline form). Otherwise `build` pays for UTF-8 validation.
- `strfuse` (`ms-mir/src/opt/strfuse.rs:20-21`) matches the externs `msrt_strbuilder_append` and `_append_int`. The new `append` must keep calling them directly, or be inlined before `strfuse` runs.
- The expected gain is one indirection and one branch per append, plus the buffer copy at `build` (`sharedbuilder.rs:135-149`). This is a hypothesis until measured.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/ownership/walk.rs` | P1 guard; D1 rejection; D2 `implicit_closes` for type-variable bindings | `crates/ms-check/tests/ownership/reject`: `carrier_escaping_capture`, `escaping_capture_needs_clone` |
| `ms-check/src/contracts.rs` | `clonable` asks `Classifier` | reject `clone_resource_in_alternative`, `clone_optional_resource_generic` (assert rejection) |
| `ms-lower/src/func.rs` | Temporary registration by class | e2e `close-scalar-resource-temporary` |
| `ms-lower/src/close.rs` | Unchanged in stages 1 and 2; instance class already used | e2e `close-generic-wrapper` (D2) |
| `ms-mir/src/verify.rs` | Reject `Copy` of a value with a closer | verifier unit test with hand-built MIR |
| `ms-check/src/ownership/classify.rs` | D4 default `Move` | ownership accept/reject |
| `ms-check/src/effects.rs`, `ms-lower/src/sharedbuilder.rs` | Builder names removed (D5, D6) | migrated builder fixtures |
| `ms-mir/src/opt/strfuse.rs` | Still matches the append externs after D6 | `bench/perf/strappend` |
| `stdlib/http.ms`, `string.ms`, `bytes.ms`, `collections.ms`, `time.ms` | D3 to D6 | stdlib conformance |
| `OWNERSHIP.md`, `documentation/core-language/types/references.md` | Restated per stage | `make docs`, book check |
| Parser, formatter, LSP | Unchanged; no syntax change | n/a |

## Alternatives

- **Do nothing.** P1 is a silent use-after-free and P2 a double close in accepted programs.
- **Stage 1 only.** This is the smallest safe version, and it is landable alone. It leaves P4 and P5 open, so stopping there is acceptable only if D1 to D7 are rejected.
- **A per-type obligations table plus MIR borrow and close-once checks** (this proposal's first draft). Rejected by review:
  - three of its five fields rename existing facts (`needs_drop`, `types::borrows`, `var fn`);
  - the MIR checks amount to a second borrow checker, conflicting with the runtime close flags (`close.rs:209-280`, `CleanupPush`).
- **Reference counting or copy-on-write for collections.** It costs every copy and mutation, and contradicts DESIGN.md decision 1 and the owner's direction.
- **A `Clonable` that may share** (the thread's first model). Rejected: it hides aliasing again.

## Staging and verification

Each step is its own PR and lands green on Linux, macOS and Windows with its repro as a test. The checks are `cargo fmt`, `clippy`, `nextest` and `make verify`, plus `make verify-full` for stage 3.

1. **Stage 1:** P1, P2, P3 and the verifier `Copy` check. No decision needed.
2. **Stage 2:** D1, then D2. Each unreproduced item gets a repro, then a fix or a drop. Gate: `bench/perf/closure-capture` at parity.
3. **Stage 3:** D3 to D7, one PR each. Gate: `strappend`, `string-lines`, `listloops`, `datastructures` and `representative` at parity or better, with a dated result section for D5 and D6.

## Open questions

All of these change user-visible behavior. Each line gives my recommendation.

- **D1.** Require `.clone()` when an escaping closure cannot move a capture. Recommend yes; it is already the documented rule.
- **D2.** Generic instances close the resources they own. Recommend yes, after D1.
- **D3.** `HttpHeaders` becomes owned, and appending needs `var`. Recommend yes.
- **D4.** The native default becomes `Move`, and time types become records. Recommend yes.
- **D5.** Remove `ListBuilder`, `MapBuilder` and `SetBuilder`. Recommend yes, since `var List` already does this.
- **D6.** `StringBuilder` and `BytesBuilder` become owned values, with a consuming `build`. Recommend yes, gated on `strappend`.
- **D7.** `Shared` carve-outs. Defer to the `Lock[T]` work.
- Out of scope: resource I/O as `var fn`. Resources are already move-only, so there is no aliasing to fix.
