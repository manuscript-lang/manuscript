[Wiki](../index.md) › [Compiler and build](index.md)

# LLVM facts need pointer provenance, and Cranelift alias regions are not markers

Verified: the CLIF-to-LLVM translation sees every address as an `i64`, so facts only reach LLVM where the translation keeps a `ptr`. It now keeps `msrt_alloc`, `msrt_alloc_zeroed` and `msrt_realloc` results (`noalias`), pointer-carrying block parameters (`ptr` phis, found by `find_ptr_params`) and entry parameters used as addresses (one `inttoptr` at entry). Checked list element accesses are tagged `ELEM_REGION` in lowering, which becomes `inbounds nuw` addresses and `mul nuw nsw` scaling.

A Cranelift alias region means "disjoint from every other region, untagged accesses included": a tagged store that no untagged load observes is dead (the `PriorityQueue` test lost a swap). Tag only functions LLVM translates (`g.llvm.is_some()`); never use a region as a mere marker for Cranelift code.

TBAA has two classes only: element accesses of lists of numbers or `Bool`s (`!8`) and of every other element type (`!9`), split by `ELEM_REGION` and `ELEM_AGG_REGION`. A buffer holds one element type, so a number buffer never holds an inner list's `{ptr, len, cap}`; `dp[i][j] = v` no longer reloads and rewrites the row header (LCS grid 41 to 34 ms). Finer classes are unsound: a record field or inner header is also read through borrowed pointers that carry no tag, so only tag accesses through `elem_addr`.

Measured (2026-11-12, same machine): none of this moves the kernels or competence suites beyond noise; `chars_1M` shifted 25% with identical optimized IR (code placement). The real vectorization blocker is checked `Int` arithmetic: `sadd.with.overflow` reductions and the cold fault exits are not vectorized by LLVM 23 (`sumi` 0.6 ns per element, a checked `y[i] += x[i] * 3` 0.78, wrapping `saxpy` 0.25).

Apply when: adding facts to the LLVM translation, or tagging memory accesses in lowering.
Evidence: [translation](../../crates/ms-clif/src/llvm_ir.rs), [element flags](../../crates/ms-clif/src/lower.rs), `make drift-check`.
Verify: `ms-conform diff --a target/release/ms --b target/release/ms --env-b MS_BACKEND=cranelift --phase run,test`.
