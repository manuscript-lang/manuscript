# Fixed-size arrays

* Status: **Proposed** (2026-11-25, `main` at 8545a74)
* Authors: Claude, for Chinmay
* Implementation: not yet implemented
* Direction: Chinmay, 2026-11-25: "we would need a new primitive for that, cause lists can grow" (so no automatic stack lists)

## Summary

- Problem: a table of known size (SHA-256's 64 words) is a growable heap `List`; Rust's `[i64; 64]` is scalarized. Instruction count differs 1.16x on `hashing`; wall time does not (143 ms against 148 ms, `bench/perf/results.md`).
- Change: a new type `Array[T]` whose length is fixed when it is made. This is a language change (new type and constructor forms).
- Decision requested: build it, or leave `hashing` at wall-time parity. Recommendation: do not build yet; prototype first (see Review).

## Motivation

- `bench/perf/suite/hashing`: Manuscript 1178M instructions, Rust 1013M (999M with overflow checks on). `sha256` keeps `w`, `h` and `k` in heap lists; Rust's are `[i64; 64]`, `[i64; 8]` and a `const`. All but 5 of 38 list accesses already lose their bounds check (range pass), but LLVM cannot keep a list's elements in registers, track their masked ranges, or unroll over them (measured: `ms emit --opt`, callgrind per line, 2026-11-25).
- `workers` (944 ms against 296 ms) is dominated by promise scheduling, not the 256-bucket list; arrays are not expected to move it.

## Proposed solution

<!-- Syntax below is new; it does not check today. -->

```manuscript
fn sum_table(k Array[Int]) Int {
    var total = 0
    for i in 0..k.length() {
        total += k[i]
    }
    return total
}

fn main() Void {
    var w = Array[Int](64, 0)
    for i in 0..64 {
        w[i] = i * i
    }
    print(sum_table(w))
}
```

`Array[T](n, fill)` makes `n` copies of `fill`; `n` may be any `Int` and is checked once. When `n` is a constant and the array never leaves the function, it lives in the frame and LLVM can keep it in registers. Otherwise it is one heap block that never grows.

## Detailed design

- **Type.** `Array[T]` is a prelude name like `List`. A value is a pointer and a length (no capacity); indexing, `length()`, `for x in a`, `a[i] = v`, `a.clone()`, `a.to_list()` and `List.to_array()` are the whole API. It has no `append`, `pop` or `extend`: that is what makes its length a fact the compiler can use.
- **Constructors.** `Array[T](n, fill)` for `fill` that is `Clonable`; the first stage takes only plain `fill` (Int, Float, Bool, payload-free enum) so no element needs a drop. `[1, 2, 3]` stays a `List`; `List.to_array()` converts, and the optimizer folds a literal conversion into a constant table.
- **Ownership.** One owner, as for `List`: passing borrows, `var` mutates in place, `move` stores, `.clone()` is the only copy. An array of owning elements is a later stage with the same aggregate-cleanup rule as `List`.
- **Indexing.** Same rule as `List`: a negative index counts from the end, out of range faults with `index N out of range for length L`. With a constant length the range pass proves most checks away.
- **Lowering.** MIR gets no new op family: `Array` reuses `list.get`, `list.set` and `list.len` on a value with `cap == len`; a new `array.new` expands to a frame slot of `n * size` bytes when `n` is a constant at the end of the MIR passes, else to `ms_alloc`. Escape (stored in a record, returned, captured, passed as `move`) forces the heap form, decided by the ownership pass that already decides `lastuse`.
- **ABI.** An `Array` passes as `(ptr, len)`, a `List` without capacity; the callee's range facts come from inlining or from `len`.
- **Generic code.** `Array[T]` is invariant like `List[T]`; there is no conversion between the two except `to_array` and `to_list`, which copy.

## Fit with the language

- **Memory model:** one owner, borrow by default, `.clone()` is the only copy; a stack array is still owned by its scope and dropped at scope end.
- **Agent ergonomics:** the diagnostic for `a.append(x)` is "Array has a fixed length; use List for a growing sequence" with the mechanical fix `a.to_list()`.
- **Names and syntax:** `Array` is new; nothing existing says "length fixed". No new keyword; the constructor reuses the type-call form `List[Int](reserve: n)`.
- **Platforms:** no platform-specific mechanism; frame size is the same everywhere.

## Measured benefit

Hypothesis, not measured: `hashing` closes its instruction gap (wall time is already level). No evidence for `workers`. A prototype of the stage-1 lowering will report callgrind counts against `bench/perf/results.md` before the stage lands.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/check` | `Array[T]` type, constructor, indexing, diagnostics | conformance accept/reject cases |
| `src/compiler/lower`, `mir` | `array.new`, frame form, `(ptr, len)` ABI | `ownership-counts` allocation count, MIR check |
| `src/compiler/opt` | range facts from the constant length; literal `to_array` fold | emit test: no bounds check on constant loops |
| `src/stdlib` (`collections.ms`) | `Array` methods, `List.to_array`, `Array.to_list` | stdlib example tests |
| docs, agent skill, lsp | collections page, idioms | `docs-check` |

## Alternatives considered

- Do nothing: `hashing` stays 1.16x Rust and `workers` 1.7x in instructions.
- Stack-allocate small non-escaping `List`s automatically: lists can grow, so the compiler would also have to prove no `append` or `extend` reaches the list; Chinmay rejected it.
- `const` tables only: fixes `k`, not the mutable `w` and `h` that carry the cost.
- Const-generic `Array[T, 64]`: gives the length in the type and the diagnostic for mismatched sizes, but adds generics over values to the checker; a first stage with a runtime-checked `n` that the optimizer folds is smaller and can grow into it.

## Stages

1. Plain-element `Array` with `new`, indexing, `length`, `for`, `clone`; frame and heap forms. Gate: `hashing` and `workers` instruction counts, conformance, `ownership-counts`.
2. `List.to_array`, `Array.to_list`, literal folding to constant tables.
3. Owning elements (`String`, records), with the drop rules of `List`.

## Open questions

- Spelling: `Array[T](n, fill)` against `[0; 64]`-style literal syntax. Recommendation: the constructor form, as no new literal syntax is needed.
- Const-generic length in the type later (`Array[Int, 64]`)? Recommendation: defer.

## Review (skeptical subagent, 2026-11-25)

- Wall time on `hashing` is at parity; the case rests on instruction count alone.
- The Rust port uses a `const` table and fixed arrays; the `.ms` port passes `k` as a heap `List`. A `const` table or scalar `var`s may close the gap with no new type. Try that first.
- Lowering is unproven: lists are three `i64` leaves reached by `inttoptr`, so a frame slot may not reach SROA. A prototype must show the IR.
- Escape and drop rules for a frame array (no `free` on an alloca, no alloca in a loop, callee that stores it) are unspecified; `list_grow`'s cap-0 view convention may be the hook.
- ABI text conflicts: `(ptr, len)` against reusing three-leaf list ops.
