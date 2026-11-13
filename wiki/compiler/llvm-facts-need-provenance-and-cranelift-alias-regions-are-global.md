[Wiki](../index.md) › [Compiler and build](index.md)

# LLVM facts need pointer provenance, and Cranelift alias regions are not markers

Verified: the CLIF-to-LLVM translation sees every address as an `i64`, so facts only reach LLVM where the translation keeps a `ptr`. It now keeps `msrt_alloc`, `msrt_alloc_zeroed` and `msrt_realloc` results (`noalias`), pointer-carrying block parameters (`ptr` phis, found by `find_ptr_params`) and entry parameters used as addresses (one `inttoptr` at entry). List element accesses carry the `REGION_IN_BOUNDS` bit in lowering when they are checked or MIR-proven (`list.get.u`), which becomes `inbounds nuw` addresses and `mul nuw nsw` scaling.

A Cranelift alias region means "disjoint from every other region, untagged accesses included": a tagged store that no untagged load observes is dead (the `PriorityQueue` test lost a swap). Tag only functions LLVM translates (`g.llvm.is_some()`); never use a region as a mere marker for Cranelift code.

TBAA has two classes only: scalar elements (`REGION_SCALAR_ELEM`) and list/string header elements (`REGION_HEADER_ELEM`); other element types stay untagged. A buffer holds one element type, so a number buffer never holds an inner list's `{ptr, len, cap}`; `dp[i][j] = v` no longer reloads and rewrites the row header (LCS grid 41 to 34 ms). Finer classes are unsound: a record field or inner header is also read through borrowed pointers that carry no tag, so only tag accesses through `elem_addr`.

Measured (2026-11-12, same machine): none of this moves the kernels or competence suites beyond noise; `chars_1M` shifted 25% with identical optimized IR (code placement). The real vectorization blocker is checked `Int` arithmetic: `sadd.with.overflow` reductions and the cold fault exits are not vectorized by LLVM 23 (`sumi` 0.6 ns per element, a checked `y[i] += x[i] * 3` 0.78, wrapping `saxpy` 0.25).

Tried without effect (2026-11-12): an entry `llvm.assume` with `dereferenceable(ptr, len * size)` for every list parameter left the LCS grid unchanged (33.7 against 35.3 ms, noise); allocator results are declared `align 16`.

Apply when: adding facts to the LLVM translation, or tagging memory accesses in lowering.
Evidence: [translation](../../crates/ms-clif/src/llvm_ir.rs), [element flags](../../crates/ms-clif/src/lower.rs), `make drift-check`.
Verify: `ms-conform diff --a target/release/ms --b target/release/ms --env-b MS_BACKEND=cranelift --phase run,test`.

## Direct MIR emission (2026-11-13)

Chinmay approved emitting LLVM IR directly from MIR (reversing the earlier rule against a second emitter); plan in `proposals/mir-to-llvm-direct.md`. A first attempt (text emitter with an in-house builder, scalar functions, records, lists and glue) was reverted: Chinmay wants the emitter built on `inkwell` from the start, not on a hand-written text builder. Per-CPU AVX2 copies are gone; LLVM does the vectorizing (`MS_VECTORIZE=off` disables it).
