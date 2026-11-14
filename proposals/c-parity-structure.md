# Structural changes for C-level speed in ordinary code

## Summary

- Problem: compiled loops are near C, but ordinary text and collection code is 1.6x to 3.3x C. The time is in native calls LLVM cannot see into, in the fresh list and copies the standard API shapes force, and in fast paths that exist only for one exact source shape.
- Change: three tracks ranked by measured gain, with the cheap measured parts staged first, then nine smaller opportunities from later passes. No new syntax or type. Two later ideas are noted, not proposed.
- Decision requested: approve the order and answer the open question on track 2. Nothing is implemented here; each stage ships with its own implementation PR.

## Status

Proposal, 2026-11-12, checked against `fff26e41`. Evidence: [`bench/perf/structural-gaps`](../bench/perf/structural-gaps/README.md). Builds on `borrowed-results.md`, `string-view.md`, `owned-parameters.md`, `stdlib-combinators-in-manuscript.md` and `declared-compiler-facts.md`. Skeptical review (2026-11-12): build with changes. Applied: lending re-ranked below inlinable code after a rerun showed it is worth 12% to 15% on `split`; the invisible entry choice withdrawn as a recommendation; cited numbers corrected; cheap stages moved first.

## Problem (measured)

- Compiled code is not the gap. Kernels with no library calls run at 0.78x to 1.23x of overflow-checked Rust ([kernels](../bench/perf/kernels/README.md), 2026-10-25); a byte-hash loop compiles to 6 instructions per byte with no runtime call.
- Library-heavy programs are. `logstats`, `csvgroup`, `wordfreq` and `grep` run at 1.59x to 3.25x C (sorting is at parity). On 2 MB of input, code compiled from `.ms` is 3%, 8% and 17% of the instructions of `grep`, `logstats` and `csvgroup`; the rest is the native runtime, the allocator and libc.
- Per-call cost: `msrt_split_next` is 109 instructions per piece; `ms_rt::string::find` is 38% of `grep`; `msrt_string_view`, a call that builds two words, is 21% of `wordfreq`. 828 runtime symbols are opaque to LLVM and 17 are inlined (`ms-rt-hot`).
- Allocation follows the API: `logstats` allocates 4.3 times per line and `csvgroup` 5.4 times per row, where C allocates 9 times in total.
- Fast paths are tied to a shape. `ms-lower` peeks at following statements through six fields (`crates/ms-lower/src/func.rs:193-238`, `stmt.rs:29`) and matches by name; the `split` view needs a parameter receiver read through `get`, so `f[5]` copies (`native/method.rs:106`, `mutation.rs:214`), and `suite/logstats/main.ms` itself takes the copying entry.

| work | recognized shape | neighboring shape | cost |
| --- | --- | --- | ---: |
| sum over map values | `for p in m.values():` | `total(m.values())` | 4.0x |
| | | `vals := m.values()` then `total(vals)` | 9.7x |
| scan characters | `for c in text.chars():` | `count_o(text.chars())` | 17.7x |
| one field of a line | `index_of` and `view` | `f := line.split(" ")` then `f[5]` | 4.0x |

- Ceiling: `logstats` as a byte scan with no per-line list runs 64.7M instructions against 112.5M (C: 37.0M), and 74 ms against 99 ms (C: 58 ms).

## Design: three tracks, in rank order

| # | Track | Expected gain | Cost | Risk |
| --- | --- | --- | --- | --- |
| 1 | Library algorithms as inlinable code | up to 40% on text programs (the byte-scan ceiling); hypothesis until stage 2 | L | Medium: compile time |
| 2 | Derived results borrow or take their receiver | 4x to 18x on the map and `chars` shapes; 18 of 62 ms on `grep`; 12% to 15% on `split` | M | Language decision |
| 3 | Allocation shapes: keyed insert, interface borrow, closure environment | 1 of the 4.3 allocations per `logstats` line; 28 ns per stored closure | S to M | Low |

### 1. Library algorithms as inlinable code

- Rule: an operation that neither allocates nor touches runtime state is `.ms` source over inline `Bytes` and `List` reads, or an `ms-rt-hot` function when it needs SIMD (`memchr`). Collections then specialize per element type instead of dispatching on `TypeDesc`.
- First family: `split`, `lines`, `fields_by`, `find`, `contains`, `scalar_at`, `view`, and `String` `length`, `starts_with` and `==` (24 to 37 instructions a call; a word scan is 2.3x C). A `for` over `split` becomes a plain loop over `memchr` results; the lookahead fields go with it.
- Each method moves only with a before/after run and a compile-time check. `Map` and `Set` lookups follow the text family, not last: an `Int` key costs 85 to 95 instructions in an opaque call that derives the slot layout from descriptors each time, and `Set[Int]` membership is 5x C in wall time.

### 2. Derived results borrow or take their receiver

- **Take**: when the receiver is a temporary or an owned value at its last use, the result reuses its storage. `decode_utf8` validates in place (the copy is 18 ms of the 62 ms `grep`, and every read-all program pays it); also `to_bytes`, `lower`, `upper`, `sorted`, `reversed`, `filter`. A take is a move of a dying value, so nothing is observable. The runtime function declares `// ms: takes:self`, beside the existing `takes:value`.
- **Lend**: `chars`, `split`, `lines`, `Map.values`, `keys`, `entries` and `List.slice` return a borrow of the receiver under the rules `view` has today: the receiver stays unchanged while the result is used, and keeping the result needs `.clone()`.

```ms
type Row:
	fields: List[String]

fn latency(line: String) Int:
	f := line.split(" ")  // lent: the pieces view `line`
	return f[5].parse_int().get(0)

fn keep(line: String) Row:
	return Row(line.split(" "))  // accepted today; under lending needs `.clone()`
```

- Under lending, `keep` is rejected with today's `view` diagnostic: `` `split` borrows `line`, which this position would keep; store `.clone()` of it, or use it in place ``.
- A lent result is immutable; a `var` binding, a capture by an escaping closure or promise, or a join with an owned value needs `.clone()` (the existing mixed-path rule). It lowers as a view result (`Func.ret_view`), which `lastuse` and `copyelim` already respect.
- The name list in `crates/ms-check/src/ownership/walk/returns.rs:962` is replaced by a `// ms: lends:self` flag.

### 3. Allocation shapes

- Keyed insert: `Map.update`, `add_default` and `m[k] = v` probe with a borrowed key and copy it only when inserting (the bound is already `Clonable`). The byte-scan `logstats` still copies one key per line (45,450 allocations for 35,521 lines).
- Interface borrow: `iface.borrow` allocates a box for a value that is only borrowed (`crates/DESIGN.md`); point at the value's slot instead.
- Closure environment: a closure that does not escape keeps its captures in the caller's frame.

### Later, not proposed here

- A combinator chain as one loop (`filter(..).map(..).sum()` is 3.0x a hand loop): follows track 1, and changes the order closures are called in.
- A four-byte text cell: `chars()` is 16 bytes a cell and `c16-maze-bfs` is 2.8x Rust on page faults ([codegen page](../bench/perf/codegen-2026-11-12.md)); needs a language decision.

### Second pass: loops, calls, exit and file work

Measured after the tracks above were started ([second pass](../bench/perf/structural-gaps/README.md)); ranked after them.

| # | Opportunity | Measured | Change | Cost |
| --- | --- | --- | --- | --- |
| 4 | Exit frees every owned value | 25 to 33 ms of a 168 to 218 ms build-then-exit program | `main` skips drops of plain memory at process exit; resources still close | S |
| 5 | Nested element writes move the row out and back | LCS over `List[List[Int]]`: 30 instructions per cell against 12 | write through the place's address; tell LLVM an element store leaves list headers unchanged, so row loads and bounds checks hoist | M |
| 6 | A file call inside concurrent work hops to a pool thread | `pargroup` 2.3x C; 4,707 `futex` and 1,505 `epoll_wait` calls for 2,000 files | keep the pool hop, which parks the task until the disk answers, and make it cheaper on every platform (one wake per file call, not three); where the OS can answer a cached read without blocking, try that first (Linux `preadv2` with `RWF_NOWAIT`, Windows overlapped `ReadFile` completing at once; macOS has no such call and keeps the hop) | M |
| 7 | Stack check per recursive call | 5 of 20.7 instructions per `fib` call, two dependent loads | keep the limit one load away, or check once per recursion cycle | S |
| 9 | A character is a `String` | tokenizer with `text.get(i) == "+"`: 11.5x C; 1.4x in compiled code once it works on code points | the compiler keeps a one-scalar `String` (`get`, a `chars()` element, a one-character literal) as its code point, so comparisons are integer compares; it becomes a `String` only where it is stored or passed | M |
| 10 | Containers written in `.ms` cannot leave a slot empty | `Deque` stores `List[T?]` and calls `msrt_list_replace` per pop: 80 instructions per push and pop, BFS 4.9x C | one internal `@std` storage primitive with take and put by index, for `Deque`, `Queue`, `PriorityQueue` and the containers track 1 moves to source | S to M |
| 11 | A change through a boxed optional field reboxes the payload | 200k tree inserts through `self.left?.insert(key)`: 4.3M allocations, 15x C's instructions | pass the box's interior address to the `var` call, as item 5 does for list rows | S to M |
| 12 | Each use of `m[k]` looks the key up again | `stats[k].count += 1` and two more field updates: a `contains` and nine lookups a pass, 1,671M instructions against 305M for one `update` call (C: 74M) | one lookup per compound assignment; reuse the slot address across statements while the map's shape is unchanged | S to M |
| 8 | Checked `Int` loops do not vectorize | 2.7x to 3.5x unchecked C on an accumulate loop; equal to C with trapping adds | a vector body that tests overflow before storing and replays the block in scalar code to fault exactly | L |

- 8 is the safety floor, not a defect: a flag tested once per loop pass was measured and gains nothing, and C with the same checks is 1.07x to 2.9x plain C on the kernels. Build it last.
- Platforms: every number here is Linux x86-64. Tracks 1 to 3 and items 5, 8, 9 and 10 change the compiler and `.ms` library, so they apply on macOS and Windows alike; items 4, 6 and 7 touch OS-specific runtime code, so each fix is written for all three platforms; measuring on Linux is enough.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` | take entries; `takes:self`, `lends:self` flags; borrowed-key insert | unit tests per entry; `count-check` allocation counts |
| `crates/ms-check` | take at last use; lend rule from the flag, name list removed | accept and reject fixtures per bound, argument, stored and `var` result |
| `crates/ms-lower` | lookahead fields and `only_read_in_place` deleted as each family moves | `shapes.ms` ratios |
| `stdlib/*.ms`, `crates/ms-rt-hot` | the first family as source or inlined helpers | engineering suite before and after |

## Alternatives

- Do nothing: sibling threads keep fixing one shape or one native at a time (four such changes this week); each neighboring shape keeps its cost.
- Widen today's elision only (accept `f[5]` and local receivers): small and worth doing if track 2's lend is declined, but it stays a lowering lookahead and gains 12% to 15% on `split`.
- Invisible lending (the checker picks lend or copy from the use): no source break, but it reverses "let's do real borrows, no compiler level magic for these" (`string-view.md`, 2026-11-09) and moves the cliff to `var`, captures and stores.
- Arenas or regions: rejected in `handler-fault-drops.md` as unsound on escape.

## Stages

1. Take entry for `decode_utf8`, and borrowed-key insert. Gate: `grep` under 1.5x C; `logstats` and `wordfreq` allocation counts.
2. Track 1 first family. Gate: `shapes.ms` `split` row under 1.5x of `index_of` and `view`; no suite slower; compile time within 5%.
3. Remaining take entries, then lending once the open question is answered. Gate: map and `chars` rows under 1.2x.
4. Interface borrow and closure environment, each with its own measurement.

## Open question

- Track 2 lend: may `split`, `lines`, `chars`, `Map.values`, `keys`, `entries` and `List.slice` return real borrows, so that keeping the result needs `.clone()`? This follows the 2026-11-09 direction and removes the cliffs, and it rejects programs that compile today (`remove-ref.md`, 2026-10-31, preferred owned results and elision). Recommendation: yes; the diagnostic already names the `.clone()` remedy.
