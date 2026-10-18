# Performance work

## String builder proposal

The 2026-10-18 linux/amd64 baseline measures appends at 5.7 ns in Manuscript
versus 2.68 ns in Go (best of 11). Go 1.25.1 reports `StringBuilder_Append`
at inlining cost 118, above its budget of 80. The wrapper combines the public
sealed-builder check with `strings.Builder`'s separate copy check, although
generated Manuscript builders are always shared through a pointer. As with
strings.Builder, the underlying Go implementation value must not be copied
after first use.

Replace only the private builder backing with a byte slice. Append retains the
seal check and uses Go append/copy; freeze seals before returning an immutable
zero-copy string. The invariant for unsafe.String is that no mutation of the
backing bytes is possible after sealing; repeated freeze returns the same bytes.
Builders remain unsynchronized mutable references. No language representation,
public signature, cancellation point, or fault contract changes.

Alternatives: retain the current implementation (safe, but keeps the measured
call overhead); copy to a string at freeze (simpler, but adds an allocation and
full copy); special-case appends in lowering (duplicates runtime policy).
Validate boundary behavior, aliases, repeated freeze, empty builders, native
calls and allocation/runtime measurements before retaining the change.

Independent skeptical review confirmed the inlining cost and approved the
proposal for supported pointer uses, conditional on those checks. It required
explicitly scoping the no-copy invariant to generated values and retaining the
cancellation check before sealing. Go callers must honor the documented no-copy
contract, just as for the previous strings.Builder backing.

## Loop polling proposal

The isolated counter loop still costs about 1.20 ns/iteration versus Go's 0.97.
Generated Go maintains a second counter only to poll every 64th iteration.
For a while loop with a literal bound and exactly one unconditional, guarded
unit step of its local Int counter, derive the poll from that counter instead:
`(counter - initial) & 63 == 63` for ascending loops (reverse the subtraction
for descending loops). Capture the initial value once. Modular Go subtraction
preserves the low six bits even when the distance exceeds MaxInt. This retains
the exact poll iterations, including a nonzero or negative initial value.

Reject the optimization if the header needs pre-statements, if any other
assignment to the counter exists, or if the body contains continue. Calls cannot
reassign a source local because closures snapshot captures. Other loops retain
the existing tick. Constant starts can let Go fold the initial value and remove
the separate increment/register; doing nothing remains preferable if measured gains disappear.
Validate negative/nonzero starts, both directions, reset/continue fallbacks,
early exits and cancellation before retaining it.

Dynamic-start measurements found about a 2% slowdown in the initial prototype:
the saved initial value and subtraction offset the removed tick. Retention is
restricted to literal starts. Eligibility is updated once per statement in a
body-local set: direct Int literal binds/assignments retain facts; every other
statement discards all facts, including nonliteral expressions, calls and branches.
Nested bodies start empty. This avoids quadratic backwards prefix scans and
does not infer facts from an enclosing branch. The emitted initial value remains
an actual counter read rather than a substituted literal.

Independent skeptical review accepted this proof and its conservative exclusions.
Native probes verify the first and second poll phases, negative/nonzero starts,
both directions, repeated/nested entry, resets and continue. Shape tests distinguish
optimized literal starts from fallback controls. Constant-start assembly confirms
the separate tick disappears; the isolated length loop improved about 20%.
The retained dynamic-start controls show approximately unchanged throughput.
