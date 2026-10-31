[Wiki](../index.md) › [Compiler and build](index.md)

# Fault locations name the failing operation's statement, without columns

Decision: the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs scope-end cleanups in reverse order before aborting ([design contract](../../crates/DESIGN.md)). Frames are `file:line in function` with no column, and a call spanning several lines reports the line of its statement's first line. A function's return-type position identifies its declaration, not a failing expression, so the located statement carries the position. Lower operands before the operation that can fault so a successful nested call does not take over the enclosing site. Do not reintroduce columns or per-call recording without a new decision.

Verified: omitted defaults lowered directly into a caller still need the callee's logical frame. Existing MIR inline scopes carry that frame without per-call runtime bookkeeping; default thunks already provide it. A source function must retain its declaration file even if its surviving instructions all come from an imported default.
Evidence: [default frame regressions](../../crates/ms-cli/tests/default_frames.rs), [default lowering](../../crates/ms-lower/src/call.rs), and the frozen `tests-e2e-testfaultsourcelocations-20` corpus fixture.

Apply when: adding lowered operations, inlining, source fault traces, or call fast paths.
Evidence: [expected failures](../../tests/conformance/expect-fail.txt), [call depth fixture](../../tests/e2e/testdata/accept/call-depth.ms), [fault and frame docs](../../documentation/contributing/compiler/lowering/cleanup-and-faults.md).
Verify: `make conform` fault-location cases; preserve frame order, line numbers, and names.

Verified: the runaway-recursion corpus count reflects a one-million raw-frame traversal budget, not a call-depth limit. Recursion is admitted by stack size. Windows must count native callers after the same `fault_vec` anchor before spending the remaining budget on generated frames; removing its old 256-frame cap without preserving that shared budget produces a different repeat count. Never manufacture a source-frame count by subtracting guessed native overhead.
Evidence: [frame walkers and budget regressions](../../crates/ms-rt/src/fault.rs), [Windows native unwind anchor](../../crates/ms-rt/src/sys_windows.rs), [stack-size contract](../../documentation/core-language/errors/faults.md).
Verify: native Windows shallow fault traces and the exact runaway-recursion corpus fixture; host synthetic-chain tests and cross-compilation alone cannot prove native unwind-entry identity.

Verified: LLVM translation must preserve cold-edge hints and identify runtime fault calls as `cold noreturn` while keeping their distinct source sites. Ordinary calls also need `nomerge`: merging equivalent calls from separate source paths can make a native fault name the other path's test or statement. Use exact runtime identities rather than a symbol prefix for semantic attributes: user function names can share a prefix. LLVM fault-frame tests must check bundled LLVM availability, not an unrelated clang installation.
Evidence: [LLVM translation and six-target object tests](../../crates/ms-clif/src/llvm_ir.rs), [actual backend frame comparison](../../crates/ms-cli/tests/llvm.rs), [runtime fault definitions](../../crates/ms-rt/src/fault.rs).
Verify: generate and verify ELF, Mach-O and COFF for x86-64 and ARM64; run LLVM/Cranelift fault-frame equality on supported native hosts. Cross-target object generation establishes code generation, not native execution or runtime ABI correctness on another operating system.

Verified: LLVM glue inlining barriers must not depend on traversal order. Caching provisional recursive depths across roots made identical inputs choose different `noinline` functions. Count a cycle's closing edge once and exclude direct self calls; at the fixed three-edge threshold, two distinct non-leaf witnesses per callee suffice to answer every root without recursive context. This derivation is specific to three edges, not a general depth algorithm.
Evidence: [glue selection and bounded-traversal regressions](../../crates/ms-clif/src/llvm_ir.rs), [deep-literal and source-frame guards](../../crates/ms-cli/tests/llvm.rs).
Verify: compare definition/edge permutations and repeated actual LLVM input captures; preserve acyclic selections, recursive owned copy/drop behavior, fault frames and the deep-literal compile guard. Deterministic attributes alone do not establish runtime performance.

---
Topics: [Errors and results](../topics/errors-and-results.md) · [Testing](../topics/testing.md)
