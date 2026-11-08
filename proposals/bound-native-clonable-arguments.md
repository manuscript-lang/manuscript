# Copy Clonable inputs at bound native consuming boundaries

## Summary

- #3053: bound list mutation with String inputs passes checking but fails lowering.
- Preserve the existing function-value borrowing contract by copying approved Clonable inputs.
- Add no rejection, consuming callable ABI, resource copying, or receiver ownership change.

## Status

Implemented candidate; 2026-11-08; source checked at main 4d9a7d15a.
Independent reviewer approved the design and final scoped diff, conditional on final checks.
The user forbids arbitrary language changes; #3049 policy changes are explicitly deferred.

## Problem

- `let set = values.set; set(0, text)` reaches a strict implicit-copy lowering error.
- `text` is String, remains with its caller, and must be copied into the list.
- Scalar bound mutators work because scalars need no owned storage copy.
- Source function-value adapters already permit Clonable parameter copies where needed.
- Native adapters currently do not mark this parameter boundary.
- Enabling every adapter copy would also silently copy non-Clonable resources.

## Design

- Reuse native parameter ownership classification; do not add native operation name lists.
- Expose declaration-order native argument modes through the checker API.
- Compute consumed positions while receiver and parameter generic types are coherent.
- Carry those positions in BoundNativeJob, excluding its captured receiver.
- Keep argument-mode identity separate from instantiated type eligibility.
- After native default/Optional unwrapping, inspect the actual argument value.
- For each consumed position, permit a boundary copy only if its concrete parameter is Clonable.
- Use the fully instantiated declared parameter type, not a non-Resource approximation.
- Exclude interfaces and unresolved variables recursively; erased payloads may lack clone.
- Conservatively leave repeated nominal-type payloads unchanged; do not add a recursive proof.
- Share the classifier traversal without altering existing Clonable checks.
- An already-owned default needs no additional copy permission.
- Mark only the resulting borrowed Value in the existing boundary_reads mechanism.
- The native lowering then uses its existing ownership conversion and clone glue.
- Preserve the job's resolved evidence scope for generated cloning.
- Borrow-only parameters and the captured/shared receiver remain unchanged.
- Defaults and written call operands retain their existing evaluation and propagation order.
- Resource and other non-Clonable inputs retain their present behavior under #3049.
- This patch does not claim to resolve or newly reject that separate contract case.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/ownership/modes.rs` | expose existing declaration-order argument modes | native consuming positions |
| checker public API | export that classification helper | compiler build |
| `ms-lower/cx.rs` | carry consuming positions in bound native job | generic receiver specialization |
| `ms-lower/closure.rs` | approve only required Clonable boundary copies | actual native adapter execution |
| source fixture | borrowed data and mutation outcomes | Debug and Release |

## Alternatives

- Do nothing leaves supported String and aggregate callable use broken.
- Mark every native thunk as an adapter: permits unsupported resource copies.
- Add a consuming callable ABI: wider language work and not authorized here.
- Reject resource methods at formation: existing source-function precedent, but a policy choice under #3049.
- Reclassify after substituting only method.ty: receiver generic metadata may no longer match.
- Reimplement mutator classification in lowering: duplicate rules would drift.

## Validation

- Named String input remains valid after set/append/insert/replace and keeps independent storage.
- Invalid indexes fault without changing the caller's input.
- Optional payloads, omitted adapter defaults, generic receiver instantiation, and named order.
- Nonconsuming adapters and direct calls retain their prior behavior.
- Verify scalar/heap Resource and function inputs do not gain clone permission or new rejection.
- Exact-head checker/lowering tests, native profiles, clippy, formatting and repository checks.
- Independent final diff review before publication; preserve all unrelated draft holds.

Local qualification: seven regression tests pass in Debug and Release with Cranelift;
53 existing native callable/default tests pass in Release; 200 checker/lower Rust tests,
scoped clippy, formatting and repository checks pass. Full CI, LLVM and platform
qualification remain separate; the local archive contains the held cleanup primitive.
