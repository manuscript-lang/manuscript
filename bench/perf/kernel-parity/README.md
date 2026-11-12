# Paired kernels against Rust, 2026-11-12

Pairs of programs with the same algorithm, written the way each language writes it (Rust with `rustc -C opt-level=3 -C overflow-checks=on -C codegen-units=1`, Manuscript with `ms build`, Release). Each prints the same checksum. Instructions executed under callgrind (Linux x86-64, LLVM release build, small allocator reservation per the [wiki](../../../wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)).

| kernel | args | ms | rust | ms / rust |
|---|---|---:|---:|---:|
| `hash` open-addressing `Int` table, insert then lookup | 200000 | 17.8M | 13.3M | 1.34x |
| `sort` insertion blocks plus bottom-up merge | 200000 | 89.0M | 65.2M | 1.37x |
| `matmul` flat `i64` matrix multiply | 200 | 155.0M | 122.6M | 1.26x |
| `lcs` two-row dynamic program | 1500 | 39.3M | 60.1M | 0.65x |
| heap ([`../heap-parity`](../heap-parity)) | 100000 | 46.0M | 47.1M | 0.98x |

## What the gaps are

Read from the hot loops with `callgrind --dump-instr=yes`:

- **matmul** (19 against 16 instructions per inner iteration): both languages check the index, but Rust keeps `i * n` and `k * n` in strength-reduced base pointers and drops the overflow check on `base + j`; Manuscript recomputes and checks `base + j` with `jo` for each of `a`, `b` and `c`. The compound update `c[x] = c[x] + ...` already needs one bounds check, and an explicit second check after the `get` is redundant (a successful access implies `x < len`). Dropping it in the range pass was tried and gave no change: LLVM already merged that compare, and the `jo` it left cost the same.
- **sort**: swapping two `var` lists (`t := a; a = b; b = t`) makes both `opt<list>`, which hides their length from the range pass, and the merge loop's `w *= 2` doubling counter ends with an unbounded interval, so `a[p]` and `a[q]` keep negative-index normalisation (`sar`, `and`, `add`, 4 extra instructions per access). A language-level swap of two lists, or range facts through `opt<list>`, would close it.
- **hash**: `main` itself is 10.3M, under Rust's 13.3M in total. The other 6.3M is `[x].repeated(n)` (via `filled`, a per-element `append(value.clone())` loop of about 6 instructions per element) that builds the two tables; Rust's `vec![-1; n]` is a vectorized fill and `vec![0; n]` is a zeroed allocation. A native fill for scalar elements closes it.

None of this is closed yet; the heap gap was (PR #3693). Ideas tried and not kept are recorded above so they are not retried blindly.
