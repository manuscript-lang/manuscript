# Two-word String `{ptr, len}`

Status: proposal, 2026-10-23, revised after a skeptical review. Owner direction: "let's do the two pointer setup" after a layout comparison, and "I want to get rid of ref counting". Supersedes the three-word shape of `owned-values.md` stage 3 (#994, closed) and changes the base of `string-ownership.md`.

## Problem

A `String` is one pointer to `StrObj {rc, drop, len, scalars, bytes}`. Every string, including a piece of `split` or the result of `trim`, is a separate object with a header, a count and a drop. The per-object cost, not allocation, is what makes string-heavy programs slower than Rust:

- Packing all pieces of one `split` into a single allocation made the CSV workload slower, not faster (87.5M to 94.9M instructions). Allocation from the size-class free list is about 10 of the roughly 130 instructions a piece costs over its life.
- The layout cannot express a borrowed view: a slice in the middle of a string has no header in front of it.

## Evidence for the change

Model benchmark (`bench/string-layout-model` in the project files): the real `ms-rt` allocator, runtime functions behind `#[inline(never)] extern "C"`, codegen-style inline refcounting, 200k CSV-style lines, minimum of 15 runs, three rounds.

| Workload | Today (one pointer, inline header) | One pointer to `{data, len, parent}` header | Two-word `{ptr, len}` |
| --- | ---: | ---: | ---: |
| split, then parse or look up each field | 23.2 ms | 21.9 ms | 17.3 ms |
| trim then slice | 4.5 ms | 4.1 ms | 1.3 ms |
| native returns a new string | 5.2 ms | | 4.4 ms |
| fields kept in a `List[String]` (two-word clones each field) | 27.7 ms | | 24.4 ms |
| first field kept as a key (two-word clones it) | 15.5 ms | 15.7 ms | 10.0 ms |

The one-pointer header with a data pointer is at parity: a view is still an object. The two-word value wins every case because a borrowed view is a plain pair with no count and no drop, and results come back in two registers.

Re-run after review, with today's layout using main's direct string drop and a two-word column without views (every piece owned):

| Workload | Today | Two-word, owned pieces | Two-word, views |
| --- | ---: | ---: | ---: |
| split, then parse or look up | 22.6 ms | 22.2 ms | 18.1 ms |
| trim then slice | 4.3 ms | 3.4 ms | 1.4 ms |
| first field kept | 15.0 ms | 14.2 ms | 10.6 ms |

The layout alone is roughly at parity; the win comes from views and from not counting. The layout is the prerequisite for both, so stage 1 is gated on no regression, and the speedup is claimed only for stages 2 and 3.

#994 (three words) was 10 to 40% slower because a 24-byte result returns through memory. A 16-byte `{ptr, len}` returns in two registers on x86-64 System V (`rax:rdx`) and AArch64 (`x0:x1`).

## Design

- **Value.** `String` is two `I64` leaves `{ptr, len}`: `ptr` points at the first byte, `len` is the byte length. Static literals point into read-only data.
- **Owned block.** During stage 1 a dynamic string's bytes follow a 16-byte header `{rc, scalars}` at `ptr - 16`, plus one trailing NUL, so behavior is unchanged. Literals keep a writable header (`STATIC_RC`) directly before their bytes, as today (`ABI.md`), so literal bytes are not deduplicated. Stage 3 removes the count: the owned block becomes the bytes plus NUL, copy (`.clone()`) allocates and copies, drop frees, and a literal is recognised by its address range instead of a header.
- **Owned vs borrowed.** A view must never be retained, released or freed. Statically, the checker's borrowed-result rule keeps views out of owning positions (with a `.clone()` fix); every copying path gets a fixture (read-only parameter stored, list element copied, closure capture, interface boxing). As a runtime guard during the transition, the top bit of `len` marks a borrowed view and drop ignores such values; it is removed once the static rule is proven by conformance and the leak sweep.
- **Empty strings** always carry a non-null `ptr` (the static empty literal), so null stays free as the `Optional` niche.
- **NUL.** Views have no terminator. Natives that hand a string to C (`ms-std-fs`, `-process`, `-system`, `-net`, `-terminal`) copy into a NUL-terminated scratch buffer, as Rust's `CString` does; an audit list goes in the stage 1 PR.
- **Interfaces.** An interface value is `{data, vtable}`; a two-word String no longer fits the data word, so boxing a String into an interface allocates a 16-byte box. Measure on the interface conformance programs.
- **Optional[String].** Null `ptr` is the `none` niche: still two leaves.
- **Slots.** `List[String]`, `Map[String, V]` keys and record fields take 16 bytes. Descriptors: `msrt_desc_string` becomes `builtin(16, 8, KIND_STRING)`.
- **Native ABI.** String parameters pass as two words `(ptr, len)`. String results return as a `#[repr(C)] StrVal {ptr, len}` by value, two registers on System V and AArch64. Windows x64 returns 16-byte structs through memory, so on that target natives use `extern "sysv64"` and codegen calls them with `CallConv::SystemV` (Cranelift and LLVM both support it there); Windows AArch64 already returns in `x0:x1`.
- **Views (stage 2).** `split`, `trim`, `slice` return borrowed `{ptr, len}` into their receiver with no count. The checker's borrowed-result rule (`OWNERSHIP.md`) already rejects a borrowed result in an owning position with a `.clone()` fix; a view never reaches a drop.

## Plan

1. **Layout and ABI, no views, count unchanged.** Two-leaf `Str` in `ms-clif` layout and lowering, descriptors, `ms-rt` string functions on `(ptr, len)`, `ms-std-*` signatures, `ms-rt-abi` constants and layout tests, `ABI.md`, `SYMBOLS.md`, `DESIGN.md`. Start from the #994 branch for the mechanical ports (natives, slots, `Optional[String]`) and drop its out-slot results. Gate: `make conform`, `make leak-check`, `cargo nextest`, the stdlib, programs and workloads benchmarks within noise of main, a cross-target return test (x86-64 System V, Windows x64 `sysv64`, AArch64 including Windows), and an LLVM IR check for two-register returns. Before porting, profile one #994 microbenchmark to confirm the out-slot return caused its slowdown.
2. **Views** for `trim`, `slice`, `split` (the list holds borrowed pairs), one family per PR, each measured.
3. **Unique ownership (no count).** Owner direction: remove reference counting from strings. Audit every copy by removing `Clone, Copy` from `StrVal` (as in `string-ownership.md` step 4), then make copy allocate and drop free. Gate on dynamic copy counts (`bench/perf/str-counts.sh`) and wall time; `strmap_10M` must stop materialising the `let w = words.get(...)` copy first.

## Alternatives

- **Do nothing.** Keeps every string an object; the remaining gap to Rust on split- and slice-heavy code stays (CSV workload 2.5x Rust).
- **One pointer to a header holding a data pointer.** Measured at parity with today; rejected.
- **Three words `{ptr, len, cap}` (#994).** Measured slower; strings are immutable, so `cap` is not needed in the value.
- **Inline small strings.** Compatible later inside the two-word value (a tagged `len`); not part of this change.
- **Fused natives or a narrow view type on today's layout** (a `fields` iterator yielding a reused view; split straight into parse). Gets part of the split win without an ABI change but leaves counting and per-object cost everywhere else, and does not move toward removing the count.

## Risks

1. Two-register returns must match the C ABI on every target; layout tests in `ms-rt-abi` and a cross-target call test guard it. Windows x64 depends on `sysv64` natives.
2. Records and collections holding strings grow by 8 bytes per string.
3. Non-ASCII `length()` keeps its cache only on owned blocks; a view recounts.
4. Every `ms-std-*` crate changes signatures (about 30 files, 300 sites); the port is mechanical but wide, and conformance plus the leak sweep are the safety net.
