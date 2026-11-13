[Wiki](../index.md)

# LLVM Language Reference (23.1.0)

Organized copy of the LLVM Language Reference for work on direct LLVM emission (`crates/ms-clif/src/mir_llvm`; see [Direct LLVM records](../compiler/direct-llvm-records-are-memory-not-leaf-bags-above-eight-leaves.md)). Read the page for the construct you emit instead of guessing semantics.

- Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html> (converted from the published HTML; text and links only, formatting simplified).
- Version: the repo pins LLVM tools `23.1.1` ([`toolchain/lld.lock`](../../toolchain/lld.lock)). The 23.1.1 manual is not published separately, so this is the 23.1.0 manual; patch releases do not change the IR language. The live <https://llvm.org/docs/LangRef.html> tracks the 24.0 development branch and can describe newer IR.
- License: LLVM documentation is Apache License 2.0 with LLVM Exceptions (<https://llvm.org/LICENSE.txt>). Copyright the LLVM Project contributors. This copy is unmodified except for format conversion.
- To refresh, bump the version above when `toolchain/lld.lock` moves, re-fetch, and regenerate. Do not hand-edit the pages.

| Page | Covers |
| --- | --- |
| [Introduction and syntax](introduction.md) | Abstract, introduction, identifiers and syntax. |
| [High level structure](high-level-structure.md) | Modules, linkage, visibility, calling conventions, global variables, functions, aliases, attributes, comdats, memory model, atomics, fast-math flags, and other module-level constructs. |
| [Type system](type-system.md) | First-class, single-value, aggregate, and opaque types. |
| [Constants and other values](constants.md) | Simple and complex constants, constant expressions, inline assembly, and metadata as values. |
| [Metadata](metadata.md) | Metadata nodes, TBAA, noalias scopes, loop metadata, debug-info metadata, and the other metadata kinds. |
| [Module flags and named metadata](named-metadata-and-module-flags.md) | Module flags and the named metadata nodes the toolchain reads. |
| [ThinLTO summary and intrinsic global variables](thinlto-and-global-variables.md) | Textual ThinLTO summary and llvm.used, llvm.global_ctors and friends. |
| [Instruction reference overview](instructions-overview.md) | How instructions are described. |
| [Terminator instructions](instructions-terminators.md) | ret, br, switch, indirectbr, invoke, callbr, resume, unreachable and the exception-handling terminators. |
| [Unary, binary, bitwise and byte operations](instructions-arithmetic.md) | fneg, add, sub, mul, div, rem, shifts, and, or, xor. |
| [Vector and aggregate operations](instructions-vector-aggregate.md) | extractelement, insertelement, shufflevector, extractvalue, insertvalue. |
| [Memory access and addressing](instructions-memory.md) | alloca, load, store, fence, cmpxchg, atomicrmw, getelementptr. |
| [Conversion operations](instructions-conversion.md) | trunc, zext, sext, fp casts, ptrtoint, inttoptr, bitcast, addrspacecast. |
| [Other operations](instructions-other.md) | icmp, fcmp, phi, select, freeze, call, va_arg, landingpad, catchpad, cleanuppad. |
| [Intrinsics: overview, varargs, GC, code generator](intrinsics-overview-and-basic.md) | Intrinsic naming and the early intrinsic groups. |
| [Intrinsics: libc, bit and arithmetic](intrinsics-libc-and-arithmetic.md) | memcpy, memmove, memset, math, bswap, ctpop, overflow, saturating and fixed-point arithmetic. |
| [Intrinsics: vector, matrix and predication](intrinsics-vector.md) | Reductions, vector manipulation, masks, matrix, vector-predication (vp.*) and masked memory intrinsics. |
| [Intrinsics: floating point](intrinsics-floating-point.md) | Float conversion, constrained FP, libm-equivalent and FP environment intrinsics. |
| [Intrinsics: general and miscellaneous](intrinsics-general.md) | llvm.dbg.*, lifetime markers, expect, assume, stackmaps, EH, trampolines, convergence, atomics, ARC and others. |
