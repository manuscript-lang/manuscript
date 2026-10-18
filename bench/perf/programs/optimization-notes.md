# Performance work

## Keep periodic native polling inline

The current-main stdlib comparison exposed list.contains at 278,595 -> 366,937
ns per search. Both versions retain the same search and polling bodies; this
comparison alone does not establish the cause. Go 1.25.1 reports Poll at cost
91 and PollIndex at 86, above budget 80, because they include CheckCancelled
(cost 77). Traversals call Poll on every element and pass a counter by address.

The first overlay kept CheckCancelled globally out of line. Although searches
improved from 360,866 to 168,913 ns, generated list iteration regressed from
0.89 to 1.25 ns and HTML escaping from 139 to 275 ns. Reject that annotation.

The narrower proposal leaves CheckCancelled and generated loops unchanged.
Only Poll and PollIndex call a private out-of-line pollCancelled helper, whose
body is exactly CheckCancelled(ctx). This should lower costs to 71/66 and allow
native traversals to inline the counter and bit test, calling the helper only
at the existing selected iteration. Both predicates, counter wrapping, context
queries, nil Execution behavior, cancellation identity and shielding remain
unchanged. This final variant must pass balanced same-revision program/stdlib
comparisons, actual call-site inlining, phase/wrap/cancellation/cleanup/source
frame tests and standalone distribution checks before retention.

Alternatives: retain per-element calls; expand polling by hand across native
loops (duplicates policy); globally outline CheckCancelled (rejected above);
use global inlining flags (rejected below). Independent skeptical review accepted
both overlay experiments conditionally and required rejecting meaningful wider
regressions. No custom Go flags or cancellation-policy changes are proposed.

The narrow candidate passed its semantic tests and the final whole-change
repeat. In the isolated 30-trial program control all rows were within about3%
except faster builder appends; the 15-trial stdlib control measured list search
345,368 -> 177,280 ns (paired95% ratio interval0.496–0.534). Nominal HTML and
other slowdowns had wide intervals including1; the final 30-trial whole-change
repeat measured HTML206 ->200.5 ns. Final list search is283,198 ->180,555 ns
(interval0.624–0.658). Keep the narrower helper. The report separately records
unresolved whole-change method/fs.stat regressions; the isolated polling control
does not establish them as effects of this helper. Existing nil-context misuse
still panics at a selected check; nil Execution remains a no-op.

## Nonnegative list reads after the current-main rebase

Main's new List.get implementation costs 99 inline points in Go 1.25.1. A
nonnegative in-range read needs only an unsigned bounds check and slice access.
Keep that path in List_Get (cost 80) and move the unchanged original body to a
private fallback for negative/out-of-range indices. This does not change index
normalization, original-index diagnostics, defaults, aliases, or cancellation.

An isolated overlay comparison measured ordinary nonnegative reads at about
2.18 -> 0.64 ns/op with zero allocations. Variable negative reads cost about
2.19 -> 2.48 ns because they take the added guard; this tradeoff is explicit.
Default paths were roughly unchanged. A branchless-normalization variant did
not improve the negative path and was discarded. A separate small-multiply
fast path nearly halved small-operand cost but slowed large operands by 16%,
so it was discarded. No inlining flags or arithmetic semantics changes ship.
Comparison-based overflow formulas (including a narrower addition-only variant)
reduced try from about 2.60 to 2.05 ns, but consistently slowed the length loop
from 0.87 to 1.15 ns, so they were also discarded.

The derived poll now uses `(distance + 1) & 63 == 0`, algebraically equivalent
to `distance & 63 == 63` even when Go Int wraps. This preserves checks before
the 64th/128th source loop bodies. A 30-run native overlay comparison improved
integer equality 1.21 -> 1.10 ns (paired after/before interval 0.871–0.949) and
matching 4.53 -> 4.21 ns (0.897–0.978). Other intervals include 1, including
the noisy map row. Dynamic starts and conservative exclusions are unchanged.

## Result construction and rejected checked-helper inlining experiment

`try` already lowers to one evaluation followed by `if result.Failed { return ... }`.
When the inner and enclosing Result types agree exactly, return that failed
result directly. Construct `ok` and `error` as typed Go literals, as other sum
constructors already do. This preserves the representation, evaluation order,
error widening and zero-error payloads; no runtime call or allocation is needed.
On Go 1.25.1 the benchmark's `chain` inlining cost falls from 91 to 80. An
early scratch generated-Go experiment measured try at 3.51 -> 2.35 ns/operation.
The final native 30-run comparison against bf8aa92e measures 3.57 -> 2.84 ns,
with a paired 95% after/before interval of 0.763–0.827.

The remaining tiny-function call barrier is Go's 57-point penalty for an
out-of-line call on the cold overflow path. `IntAdd` has cost 78, so `checked`
(95 after direct Result construction) and `Acc.bump` (89) exceed the normal
80-point budget. Experimentally compiling the runtime with the pinned Go
compiler's `-l=4` reduces the penalty, while retaining the ordinary budget and
explicit `//go:noinline` directives. In particular, `intOverflow` itself becomes
inlineable, reducing `IntAdd` to cost 32; the flag affects non-leaf calls throughout
the runtime, so broader measurements are necessary. The generated functions then fit: costs
49, 72 and 43 for `checked`, `chain` and `Acc.bump`. A 30-run balanced comparison
of module-wide `-l=4` against direct Result construction alone measured method
2.37 -> 0.70 ns and try 2.35 -> 1.50 ns, with no benchmark checksum changes.

Propose applying `-l=4` only to the native runtime package for optimized build
types, leaving Debug unoptimized and leaving Go's standard library and generated
application under their normal settings. First confirm the runtime-only control
has the same benefit. Do not add unchecked arithmetic or weaken cancellation.
The pinned toolchain owns this flag, and emitted standalone Go remains valid
under ordinary Go compilation (including the direct-Result improvement).

Alternatives: keep ordinary inlining (retains measured small-function barriers),
emit arithmetic checks at every call site (duplicates runtime policy), change
Result to Go multiple returns (changes the canonical representation), or enable
`-l=4` for every package (unnecessary scope). Retain the build change only after
checking balanced benchmarks, stdlib workloads, warm build time/binary size,
fault frames, numeric boundaries, cleanup, replay/cache identity, native build
types and distribution checks. Recheck the flag and measurements on Go upgrades.

Independent skeptical review accepted the runtime-only proposal conditionally.
The runtime-only 30-run control measured method 2.31 -> 0.69 ns and try
2.31 -> 1.49 ns; other rows were roughly stable and match improved. It required
exact flag-scope assertions, native semantic/frame/cleanup checks, replay and
distribution checks, stdlib and build latency measurements, and actual ELF text
size instead of rounded total file size. Existing replay keys include native
flags and embedded implementation sources already invalidate build identity.

The production build experiment failed that retention gate. In ten alternating
stdlib trials per revision, interpolation measured 82 -> 96.5 ns, CSV parsing
186 -> 237 ns, and queue enqueue/dequeue 10.5 -> 14 ns. The actual native program
control also showed integer equality 1.19 -> 1.37 ns despite faster method/try
workloads. Keeping `intOverflow` out of line in a further temporary overlay
recovered some loops but regressed generic accumulation. The reviewer agreed to
reject the flag. No compiler flag, package split, or arithmetic cold-helper annotation is
retained from that experiment. Its only retained changes are direct Result
construction and exact-type failure returns.
The rejected experiment's raw data remains available with the results.

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
