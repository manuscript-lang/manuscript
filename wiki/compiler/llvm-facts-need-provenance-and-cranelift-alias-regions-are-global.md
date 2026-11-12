[Wiki](../index.md) › [Compiler and build](index.md)

# LLVM facts need pointer provenance, and Cranelift alias regions are not markers

Verified: the CLIF-to-LLVM translation sees every address as an `i64`, so facts only reach LLVM where the translation keeps a `ptr`. It now keeps `msrt_alloc`, `msrt_alloc_zeroed` and `msrt_realloc` results (`noalias`), pointer-carrying block parameters (`ptr` phis, found by `find_ptr_params`) and entry parameters used as addresses (one `inttoptr` at entry). Checked list element accesses are tagged `ELEM_REGION` in lowering, which becomes `inbounds nuw` addresses and `mul nuw nsw` scaling.

A Cranelift alias region means "disjoint from every other region, untagged accesses included": a tagged store that no untagged load observes is dead (the `PriorityQueue` test lost a swap). Tag only functions LLVM translates (`g.llvm.is_some()`); never use a region as a mere marker for Cranelift code.

Rejected: TBAA by element or field kind. A `List[List[T]]` element is a list header that a borrowed pointer reads through another tag, so no type-based class is disjoint.

Measured (2026-11-12, same machine): none of this moves the kernels or competence suites beyond noise; `chars_1M` shifted 25% with identical optimized IR (code placement). The real vectorization blocker is checked `Int` arithmetic: `sadd.with.overflow` reductions and the cold fault exits are not vectorized by LLVM 23 (`sumi` 0.6 ns per element, a checked `y[i] += x[i] * 3` 0.78, wrapping `saxpy` 0.25).

Apply when: adding facts to the LLVM translation, or tagging memory accesses in lowering.
Evidence: [translation](../../crates/ms-clif/src/llvm_ir.rs), [element flags](../../crates/ms-clif/src/lower.rs), `make drift-check`.
Verify: `ms-conform diff --a target/release/ms --b target/release/ms --env-b MS_BACKEND=cranelift --phase run,test`.
