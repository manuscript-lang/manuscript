[Wiki](../index.md) › [Compiler and build](index.md)

# Fault locations name the failing operation's statement, without columns

Decision: the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs scope-end cleanups in reverse order before aborting ([design contract](../../crates/DESIGN.md)). Frames are `file:line in function` with no column, and a call spanning several lines reports the line of its statement's first line. A function's return-type position identifies its declaration, not a failing expression, so the located statement carries the position.

Apply when: adding lowered operations, inlining, source fault traces, or call fast paths.
Evidence: [default frame regressions](../../crates/ms-cli/tests/default_frames.rs), [default lowering](../../crates/ms-lower/src/call.rs), and the frozen `tests-e2e-testfaultsourcelocations-20` corpus fixture.
Evidence: [expected failures](../../tests/conformance/expect-fail.txt), [call depth fixture](../../tests/conformance/fixtures/e2e/accept/call-depth.ms), [fault and frame docs](../../documentation/contributing/compiler/lowering/cleanup-and-faults.md).
Evidence: [frame walkers and budget regressions](../../crates/ms-rt/src/fault.rs), [Windows native unwind anchor](../../crates/ms-rt/src/sys_windows.rs), [stack-size contract](../../documentation/core-language/errors/faults.md).
Evidence: [LLVM translation and six-target object tests](../../crates/ms-clif/src/llvm_ir.rs), [actual backend frame comparison](../../crates/ms-cli/tests/llvm.rs), [runtime fault definitions](../../crates/ms-rt/src/fault.rs).
Evidence: [glue selection and bounded-traversal regressions](../../crates/ms-clif/src/llvm_ir.rs), [deep-literal and source-frame guards](../../crates/ms-cli/tests/llvm.rs).
Verify: `make conform` fault-location cases; preserve frame order, line numbers, and names.
Verify: native Windows shallow fault traces and the exact runaway-recursion corpus fixture; host synthetic-chain tests and cross-compilation alone cannot prove native unwind-entry identity.
Verify: generate and verify ELF, Mach-O and COFF for x86-64 and ARM64; run LLVM/Cranelift fault-frame equality on supported native hosts. Cross-target object generation establishes code generation, not native execution or runtime ABI correctness on another operating system.
Verify: compare definition/edge permutations and repeated actual LLVM input captures; preserve acyclic selections, recursive owned copy/drop behavior, fault frames and the deep-literal compile guard. Deterministic attributes alone do not establish runtime performance.
Potentially faulting LLVM calls use `notail` as well as `nomerge`: eliminating a tail caller loses its source frame, even with frame pointers enabled. Inlining keeps its debug scope. Proven non-faulting, callback-free runtime helpers (the existing `pure_runtime_attrs` classification) and source-less CPU dispatchers retain tail-call optimization. Indirect calls have no such proof. Recursive source calls keep diagnostic frames and consume stack under the documented byte limit; constant-stack tail recursion is not a language guarantee. Verify pure-helper, direct and indirect call-return wrappers through LLVM's optimizer, bounded/runaway final recursion, and native Windows task-fault traces; do not remove a missing wrapper from the corpus expectation.
