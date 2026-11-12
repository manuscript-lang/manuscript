# Paired kernels against Rust, 2026-11-12

Pairs of programs with the same algorithm, written the way each language writes it (Rust with `rustc -C opt-level=3 -C overflow-checks=on -C codegen-units=1`, Manuscript with `ms build`, Release). Each prints the same checksum. Instructions executed under callgrind (Linux x86-64, LLVM release build, small allocator reservation per the [wiki](../../../wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)).

| kernel | args | ms | rust | ms / rust |
|---|---|---:|---:|---:|
| `hash` open-addressing `Int` table, insert then lookup | 200000 | 14.3M | 13.3M | 1.07x |
| `sort` insertion blocks plus bottom-up merge | 200000 | 67.1M | 65.2M | 1.03x |
| `matmul` flat `i64` matrix multiply | 200 | 130.9M | 122.6M | 1.07x |
| `lcs` two-row dynamic program | 1500 | 39.3M | 60.1M | 0.65x |
| heap ([`../heap-parity`](../heap-parity)) | 100000 | 46.0M | 47.1M | 0.98x |

## What the gaps are

Read from the hot loops with `callgrind --dump-instr=yes`:

- **matmul**: was 155.0M (1.26x, 19 against 16 instructions per inner iteration). Rust drops the overflow check on `base + j`; Manuscript checked `i * n` and `i * n + j` for each of `a`, `b` and `c` with `jo`. With the checked square `n * n` already computed for the allocation, `0 <= x, j < n` bounds `x * n + j` by `n * n - 1`, so the range pass now turns those checks into plain `imul`/`iadd` (130.9M). The compound update's second bounds check was already merged by LLVM, and dropping it in the range pass changed nothing. What remains is the checked `x * b[..]` and `+ ...` data arithmetic, which Rust's wrapping release build does not do.
- **sort**: was 89.0M (1.37x). Every `a[p]`/`a[q]` in the merge loop paid negative-index normalisation (`sar`, `and`, `add`, about 4 instructions) and every store a bounds check, for three reasons found in the range pass: (1) an `iadd`/`imul` that range had proved non-wrapping and turned unchecked was evaluated as a wrapping op afterwards, so `w *= 2` and `q += 1` went to top and lost their lower bound; such results are now recorded in `Func::exact` and keep the interval of their checked twin; (2) a refinement disjoint from an early, still-growing interval was dropped instead of taken, which left an interval below zero in `q`'s cycle for good; (3) the swapped `var` lists are `opt<list>`, which hid their lengths, so lengths now flow through `opt.some`/`opt.get`/`opt.unbox`. What remains are the bounds checks Rust also has.
- **hash**: was 17.8M (1.34x). `main` itself is 10.3M; the rest was `[x].repeated(n)` (via `filled`), an element-by-element `append(value.clone())` loop of about 6 instructions per element, against Rust's vectorized or zeroed fill. `repeated` is now the native `msrt_list_repeat` (plain elements copy once and double in place) and `filled` calls it: 14.3M. The remaining 1.0M is the allocation and the first-touch of a longer table than Rust's `calloc` path.

The heap gap was closed in PR #3693 and the hash gap by the native repeat. Ideas tried and not kept are recorded above so they are not retried blindly.
