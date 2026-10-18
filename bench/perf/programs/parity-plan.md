# Measured proposals and review decisions

This is the proposal/review record. The paragraphs below preserve pre-experiment
reasoning; each outcome states what actually ships. The [final report](results.md)
and [raw evidence](../results/2026-10-18-linux-amd64/complete-parity/) are authoritative.
Independent skeptical review challenged each structural increment before its
implementation. No deferred/rejected experiment is included in production.
Intermediate Go comparisons used the inherited ordinary default-flags Go binary;
the final report rebuilds all languages with identical CGO/trim/link flags.

## Preserve eager faults while making arithmetic inlineable

**Outcome:** Retained only for IntAdd and IntMultiply, with original overflow predicates and eager faults. The all-four-helper prototype was rejected. Source-frame and native numeric checks pass.

The current program controls report method2.59 vs Go0.27 ns, try2.61 vs0.58,
generic accumulation0.87 vs0.28 and length0.88 vs0.28. Checked IntAdd costs78
inline points; its cold direct call costs57. The method/checked source helpers
therefore exceed Go's ordinary budget80. Removing overflow checks is not allowed.

The independent skeptical reviewer identified a narrower alternative to changing
fault recovery: Go charges calls through function parameters17 inline points.
Keep each exported arithmetic helper's signature, but delegate its existing
algorithm to a private helper receiving the fixed intOverflow function. The
callback runs only under the identical overflow predicate. One helper owns each
algorithm; wrappers do not duplicate it. All faults retain eager messages,
frames, panic type, cleanup and async handling. No special compiler flag or new
representation is needed.

A Go1.25.1 scratch probe reports private add38, public add44, method55, checked59,
and chain76, all within80. Assembly shows arithmetic in the source loop, no
success-path method/helper call, and the overflow callback only on the fault
branch. The callback may remain indirect on that cold branch; this is acceptable
only if source frames and faults remain exact. Native code and the full workload
suite still need measurement; scratch costs are not a retention result.

Required: actual runtime and generated-function costs/assembly, balanced program
and all66 stdlib cases, allocation counts, integer extreme/sign/overflow cases,
optimized/debug/standalone source frames, cancellation/cleanup and distribution
checks. Keep only measured improvements without meaningful wider regressions.
Reassess Go's function-parameter call cost on toolchain upgrades.

Alternatives: retain the call barrier; global -l=4 (previously regressed unrelated
helpers); a separate specially compiled numeric package (adds a layer/flag scope);
direct panic with deferred frame materialization (changes24 recovery boundaries).
The last approach passed a tiny cost/stack feasibility probe, but the reviewer
required testing this callback alternative first. Do not change Fault/recovery
semantics when this simpler mechanism suffices.

## Eliminate tail Result unwrap/rewrap

**Outcome:** Retained for exact adjacent identity tails. Function payloads, widening, mutable bindings and Debug keep the existing path.

The real callback experiment reduces checked to cost64, but chain rises to87
because Go starts pricing the now-inlineable checked body instead of a57-point
call. Named results lower the arithmetic helper further, but a redundant tail
`let v = try call(); return ok(v)` still crosses the inline budget. An exact-type
Result can instead be returned directly, since both success and failure are the
same Result. This erases the temporary, test and reconstruction while preserving
single evaluation, error views/aliases and early exit. Require exact checked
Result identity and checked binding/constructor identities; reject conversions,
widening, mutable/reassigned intermediates and any intervening statements.

Preserve the original form in Debug builds and debug-local inventory, so source
locals and breakpoints remain usable. Add an explicit lower option for preserving
bindings (do not overload the literal-build option). Keep source directives on
the operand's original statement; no call/fault frame disappears beyond ordinary
Go inlining. Test native success/failure/empty errors, once-only effects, aliases,
exact generic instantiation, widening/different output types and Debug locals.
This is a local adjacent-tail simplification, not a second optimizer IR.

## Prove bounded scalar arithmetic first

**Outcome:** Retained with exact arithmetic, all-modified invalidation, prefix budgets, callable isolation and paired fallbacks.

A generated-Go-only control removed four mathematically redundant additions:
loop hits<=10M; sum(i) for i<1M<=499999500000; sum(length)<=100M; and a traversal
of a freshly filled List[Int] with<=1M elements each0..999999. Thirty balanced
trials measured generic0.90->0.31 ns (Go0.30), equality1.01 vs Go1.06, traversal
0.49 vs Go0.40, and length0.62 vs Go0.28. This control is not production proof;
it establishes benefit for a checked-fact optimization. Globally batching loop
polls also helped selected rows but regressed try, so do not retain that variant.

Propose one conservative function-local interval analysis in lower, producing
only a set of proven-safe Int +/- syntax nodes. The independent reviewer requires
a scalar-only first increment: defer multiplication and private-list propagation.
Only those nodes lower to ordinary Go operators; every unknown case retains the
existing checked helper. All supported native targets are64-bit; proofs use
signed64 endpoints with checked compile-time arithmetic. Cancellation selection,
query phase, fault messages and evaluation order remain unchanged.

Facts use checked binding identity, scoped to one concrete lowered function.
Literal binds/assignments update ranges; unknown expressions use the full Int
range. A verified one-parameter/one-return identity function preserves its
argument interval without changing the call. Branches analyze from a rollback
checkpoint and conservatively forget facts at the join. Use an undo journal and
epoch-tagged entries, not copying all variables per branch/loop. Lambdas analyze
their own bodies and inherit no numeric facts.

Eligible loops have a known finite iteration upper bound: an exact-start,
strict-literal-bound, unique unconditional unit-step counter without continue,
with no resets or early exits. List traversals remain a separate proposal.
Reject nested loops for this loop-summary proof (analyze inner loops separately)
and any counter reset/extra write. Summarize each body's own non-nested writes
once. Before computing update deltas, replace ALL modified scalar ranges with
unknown except the induction counter: an initial value of another accumulator
is not a loop invariant. A carry binding must have only additive/subtractive
updates independent of itself; bound every update by the loop count, including
conditional updates, and retain checked code if any endpoint calculation fails. Sum negative and
positive contributions separately, including optional branches and every prefix;
a safe net delta does not prove that intermediate updates are safe.
Install the conservative carry invariants before analyzing the body once, then
restore the enclosing facts and apply proved postconditions. Unknown loops
forget facts before/after their body. Do not rescan prefixes or flatten nested
summaries repeatedly; N/2N/4N compiler scaling is a retention check.

## Deferred private-list increment (requires separate review)

**Outcome:** Superseded by the narrower closed Int-list proposal below. No general list ownership or mutation analysis ships.

List facts would initially cover only fresh, immutable local List[Int] bindings. A
single checked-use inventory must prove every reference is a direct canonical
append/get/length receiver or a direct for iterable, never an alias, argument,
return, bound method, nested callable capture, assignment target or conversion.
Only these lists get length/value facts. A fresh empty/literal list has known
length and element bounds. Count appends in eligible loops; before computing
new element bounds, invalidate ALL mutated lists' element facts, so self/peer
recursive appends cannot reuse their initial bounds. Length bounds include all
possible appends; exact counts require unconditional appends and no early break.
Unknown loops/joins discard list facts. Stable exact length can replace the
canonical O(1) length read; preserve evaluation of the receiver. An Int get
returns only the stored element bounds (plus any supplied default's bounds);
a missing no-default lookup still faults normally before arithmetic executes.

Required: proof-shape pairs and native overflow edges (Min/Max, ascending and
descending, wrong/reset steps, continue/nesting, conditional/multiple/cross-carry
updates), unknown/dynamic paths, effectful calls and early exits. List tests must
cover mutation, defaults, empty lists, alias escape, callbacks, bound members,
loops that mutate during traversal and unsupported custom operations. Debug
preserves source binding structure; all unknown cases must remain checked.
Use math/big as a test oracle for endpoint calculations, not unchecked host
arithmetic. Retain only after actual compiler scaling, native fault/cancellation
phase/cleanup/source-frame tests and balanced full program/library controls.

## Closed local Map backend proposal

**Outcome:** Retained after independent review, allocation controls and native alias/absence/evaluation tests. One Go type remains; all consumers select the exclusive internal invariant together.

The measured map put/get workload remains approximately 63 ns per operation
versus handwritten Go 32 ns. Its fresh local map is used only by direct add
statements and get calls; neither insertion order nor concurrent sharing can be
observed. Current lowering still maintains ordered slots and performs sharing
diagnostics, plus generic helper calls. Merely dropping these globally would
break public semantics. Doing nothing leaves the largest container gap.

Propose a separate, conservative checked-use inventory for fresh immutable local
Map constructor bindings. Inventory every executable reference (including defaults,
match arms and nested callable captures). Permit only a name used as the direct
receiver of the canonical native Map.add/get/length/contains call. add must
be a root expression statement whose returned map is discarded. Reject aliases,
arguments, return values, interpolation/equality, iteration, views, bound members,
mutable bindings, assignment targets, chained add results and captures. Reject
any reference across a nested callable boundary even if its immediate parent
looks like a permitted operation. Only canonical native Go-equality keys qualify;
visible custom Hashable/Equal evidence must retain the existing path. Unsupported
or uncertain uses retain ordinary ordered maps. Debug retains ordinary maps.

Keep the same *rt.Map[K,V] Go type for every Manuscript Map. Reuse the existing Int index map as key-to-value storage with dedicated
compiler-only constructor/operation helpers, selected
only for the closed local proof. Ordinary Map constructors/operations continue
to use ordered storage and guards. Local operations preserve duplicate replacement,
missing Optional, native key equality (including NaN), reference payloads,
argument evaluation, fault/cancellation behavior and all existing source frames.
The proof establishes why order/sharing cannot be observed; there is no global
semantic relaxation, boxing, conversion or second Go type for Map.

Alternatives: keep all current overhead; improve generic helpers without removing
ordered/atomic work (worth separate measurement); lower to a different Go map
type (violates the single-representation contract); globally disable ordering or
sharing checks (invalid); profile-guided escape guesses (not a proof). Require
paired accepted/rejected shapes, local custom equality, alias/capture/returned-add
fallbacks, missing lookups, NaN, overwritten keys, evaluation order and native/
standalone controls. Measure all program and standard-library cases and inspect
allocations before retaining. A generated-Go plain-map control is only evidence
of an upper bound, never the production escape proof.

## Next increment: closed Int-list facts

**Outcome:** Retained after separate review and native overflow/default/alias/hidden-mutation checks. Ordinary accesses and append operations remain intact.

The scalar pass now executes native overflow/prefix/peer/after-step tests and
measures generic 0.33 vs Go 0.29 ns. Its isolated pass scales approximately
0.43/0.90/1.72 ms at 128/256/512 loops; allocation counts scale 1235/2402/4739.
The end-to-end first doubling was 2.3x, so profiling was checked: GC scanning and
printing dominate; the new pass's AST traversal and bounded endpoint work remain
linear. Keep the independent review's scalar-only checkpoint before this increment.

Propose extending the already measured closed-use inventory to fresh immutable
List[Int] literals, with only direct native append statements, get/length calls,
and direct for iterables. Every other reference, capture, alias, bound member,
custom/native override or escape drops the facts. Use the same full callable
inventory (including defaults/match arms and descendant captures), inherited by
lambdas without rescanning. List retains its ordinary runtime storage and methods.

Extend the existing epoch/journal facts with immutable list summaries: length
interval, element interval, and whether an initially empty list has any elements.
Literal construction and a straight-line append transfer these facts. A canonical
get preserves the element bounds, unioned with a supplied default; missing reads
still execute and fault normally. An exactly known length may replace a direct
immutable name receiver's length call with a literal; evaluating that name has no
effects. No arbitrary receiver expression is removed.

For the already eligible strict unit-step loops, collect direct append statements
and their conditional status while collecting scalar writes. Before deriving ANY
deltas, invalidate every modified scalar and every appended list's length and
element facts. This prevents self/peer recursive appends or length-based append
values from reusing initial facts. Derive new element bounds only from induction
ranges, literals and unmodified facts; union with saved initial elements. Length
upper bounds include every syntactic append times the iteration bound; exact
post-lengths require all appends unconditional and a known initial exact length.
Use checked exact endpoint/count math. Install conservative invariants before a
single body transfer, restore, then apply only proved postconditions.

A direct for over a proved closed Int list may use its entry length upper bound
and element interval for additive carry proofs. Reuse the same bounded-body
summary; reject early exits, nested loops, expression bodies and ALL appends in
this first for-summary increment. This preserves traversal/cancellation and
avoids reasoning about mutation during iteration. Unknown joins/loops discard
all list facts with the existing epochs. No multiplication or record proof yet.

Required: paired alias/capture/default/bound-member/unsupported-mutation fallbacks,
self/peer recursive appends, conditional appends, default/missing reads, empty
lists, negative indices, mutation during traversal, generic instances and nested
callables. Native overflow/fault/cleanup/cancellation and N/2N/4N scaling remain
retention gates. Human-proved generated controls show length 0.62 vs Go0.28 and
list traversal0.49 vs0.40 after redundant checked sums are removed; exact length
propagation should additionally let Go hoist/fold the stable length.

## Narrow multiply increment proposal

**Outcome:** Retained exact corner-product range proof and unchanged-algorithm cold callback. Endpoint/interior oracle and numeric/source-frame checks pass.

The existing runtime already uses corrected high/low-word multiplication, not
divide-back. Keep that algorithm. A standalone additive range proof cannot bound
the map fill's `i * 2`; four exact endpoint products can prove the same bounded
operation with no runtime check. Extend safe arithmetic annotations only to
multiplication whose complete signed interval fits. Use exact math/big endpoint
products and test with an independent endpoint oracle and native overflow edges.
Every unsupported/overflowing interval retains IntMultiply. This removes no
operand evaluation, defaults, faults elsewhere, or cancellation.

Separately retest only IntMultiply's fixed cold-callback wrapper against the
CURRENT named IntAdd + tail Result + scalar/list/map proofs. The earlier all-four
helper experiment was rejected because it regressed try/equality/library rows;
it is not retention evidence. Tail simplification and scalar proofs have since
removed the relevant inlining barriers. The original multiply predicate and
32-bit branch remain unchanged, replacing only the cold intOverflow call with
its fixed callback. This can remove calls inside area even if area remains above
Go's ordinary inline budget. Measure actual costs/assembly, allocations, native
fault frames/cleanup and balanced all-workload regressions. Reject it again if
those gates fail; do not retain Subtract/Negate wrapper changes without evidence.

## Narrow constant-stride cancellation batching proposal

**Outcome:** Retained only the reviewed two-scalar, independent constant-stride scope. Native observer tests verify every original query state, partial tails, signed limits and cancellation cleanup.

The broad loop-batching experiment was rejected for regressions. A new
length-only generated-Go control, AFTER closed-list and scalar proofs, measures
length0.59->0.32 ns vs Go0.28 in30 balanced trials, without a material program
regression. A three-loop control helped equality slightly but regressed builder;
reject the broader variant. The source body's literal length and sum are now
native; the remaining per-iteration polling predicate costs as much as the work.

Propose a much narrower first scope: exact-start strict ascending literal-bound
unit-step loops with at least256 known iterations, exactly TWO unconditional
simple Int assignments, and the counter increment last. The other assignment
must be a proven-safe additive carry by a singleton constant. Its RHS may contain
only literals, unchanged local Int names, proven-native +/- expressions and a
proved exact direct-name List.length. No other calls, branching, source bindings,
field/index mutation, allocations, nested loops, break/continue, cleanup, lambdas,
matches or unchecked/faulting arithmetic. Debug retains original loops.

Emit63 original iterations in a plain inner loop, then (if another iteration
exists) CheckCancelled followed by one original body. Repeat. Queries still occur
BEFORE source iterations64/128/etc and nowhere else; zero-tail behavior and
normal final counter/carry match. The strict guard and finite distance proof make
limit-counter and counter+63 safe in the chunk header. Generate the source body
once and print it in the two mutually exclusive scopes with identical source
locations; no additional source expression executes. Existing outer cleanup and
cancellation unwinding stay unchanged.

This is a cancellation lowering change and requires independent review. Required
native instrumentation observes counter/carry values exactly at generated query
sites, including partial final chunks and near-Min/Max starts, query-triggered
cancellation and surrounding cleanup. Paired rejection tests retain ordinary
polling for every excluded shape. Compare all programs/library cases, scaling,
Debug and standalone code; reject if wider results regress. Doing nothing keeps
an avoidable hot predicate; relaxing polling frequency or phase is not an option.

## Closed one-field record method proposal

**Outcome:** Retained only exact proved one-field updates. General methods, unknown intervals, aliases, captures, defaults and generic records keep ordinary calls. Paired/native/standalone/frame checks pass.

The method control still measures roughly0.86 vs Go0.29 ns after ordinary Go
inlining. The caller constructs Acc(0), then performs1M discarded bump(1) calls;
all increments fit. The remaining checked field additions are redundant in this
closed caller, but the general method must still fault for arbitrary inputs.
A generated-Go-only unchecked-field control is required before implementation.

Propose a narrowly proved caller expansion: only a fresh immutable local source
record with exactly one concrete Int field, an explicit literal initializer and
no generic type arguments. Inventory every use with the existing two-pass closed
collection scanner. Permit only read-only direct field access (copying Int) and
discarded direct source method calls. Reject every alias/capture/view/bound method,
receiver argument/return, explicit field write and any other method. Disable in
Debug and local implementation scopes. Keep the same ordinary record pointer.

An eligible method has exactly one immutable Int parameter without a default and
exactly two source statements: assign self.field +/- that parameter; return the
same field. Match checked self/parameter identities, resolved method declaration,
receiver nominal identity, the unique checked Int field and absence of conversion
metadata. No calls, cleanup, loops, recursion, defaults or other behavior exist
inside this body. Preserve general method lowering for every unproved call.

Use the single field's interval in the existing epoch/journal numeric fact for
its record binding. Collect matched root method calls as additive cell updates
in existing bounded-body summaries; include them in ALL-modified invalidation
before deriving scalar/list/record deltas. Peer field and accumulator starts are
not invariants. Sum negative/positive update budgets separately over loop count,
including optional updates and every prefix, then install all facts together.
A call is annotated only when its current field interval +/- evaluated argument
interval fits; otherwise keep the original checked method. Unknown flow kills
facts. Field reads contribute bounds only for inventoried record references.

At an annotated call, retain normal receiver/argument evaluation and emit the
single native field update, then its Int result (discarded by the source).
Execute each call individually; no aggregate update, field caching or layout
change. The omitted checked branch cannot fault under the proof; there is no
callee cancellation/depth/cleanup work to drop. Debug retains source calls and
frames. This changes caller lowering, not the method's global semantics.

Alternatives: keep checked native addition (measured3x gap); globally unchecked
fields (invalid); clone source methods for each caller interval (larger ABI/cache
machinery); general record escape/mutation analysis (out of scope). Required:
paired proof/fallback shapes, native prefix/peer/reset/default/alias/capture/
unknown-argument overflow and source-frame checks, parameter/receiver evaluation,
normal pointer identity, Debug/standalone execution, scaling and full balanced
program/library/allocation controls. Retain only measured gains without wider
regressions; no general record ownership or method inlining framework.

## Read-line payload-elision proposal

**Outcome:** Retained after runtime and generated-Go controls. Materialization alone is omitted after existing checks; ordinary text reads keep allocations and behavior. Buffered/custom query, cleanup, consumption and frame checks pass.

Line counting remains roughly1.25x Go. The idiomatic source helper only returns
whether read_line succeeded with some line: `if let line = read_line(input):
return line.is_some(); return false`. The immutable String payload never escapes
or is inspected, yet the runtime still allocates/copies it on every valid line.
Locking, UTF-8 validation, consumption and errors must stay unchanged.

Propose a local checked tail-pair simplification, analogous to exact Result tails:
only the canonical native read_line Result[Optional[String],IoError], a checked
success binding used solely by canonical Optional.is_some in one return, no else,
then literal return false in an enclosing Bool function. Preserve argument/default
evaluation and source call position; Debug/local inventory keeps original code.
No source API changes. Reject other functions, aliases, payload uses, extra effects,
conversions or different branches.

Add compiler-only Io_HasLine with the same native parameters returning Bool.
Refactor existing Io_ReadLine into an inlineable ordinary wrapper of the unchanged
private algorithm with keepText=true; Io_HasLine calls it with keepText=false and
returns !Failed && Val.Some. In the private buffered success/tail paths only,
keepText=false returns some("") after the SAME UTF-8/limit checks and buffer
consumption instead of allocating the unobserved text. Custom byte-stream fallback
may keep the original allocation initially. Both paths share one algorithm;
ordinary source read_line always receives keepText=true and full text. No extra
queries, relaxed validation, lock removal, error collapse observable by source,
or Result representation change.

Measure a runtime Go allocation/time control plus generated-Go Bool-only control
BEFORE retaining compiler selection. Require paired source-shape fallbacks and
native buffered/custom streams, empty/EOF/CRLF, UTF-8, size limits, read failures,
effectful arguments, cancellation queries, cleanup and fault-source frames.
Compare actual text-returning read_line against unchanged Go and before runtime
for regressions; keep the wrapper refactor only if wider controls pass. Doing
nothing leaves a dead payload allocation; globally dropping text/UTF-8/locks or
adding a source API is not justified.

## Closed Int map key-presence proposal

**Outcome:** Deferred, not implemented. Its manual control saved only about6%; line payload elision already brings the complete map workload close to Go. Review found the added proof machinery unjustified by that gain.

The closed storage backend removes order and mutation guards, but .get(key).get()
still performs Go mapaccess2 plus Optional presence/fault checks for keys a previous
complete fill has inserted. Handwritten Go uses mapaccess1. First measure a manual
generated-Go known-present control under the human proof of the unchanged 0..7999
fill/read workload; retain compiler work only if it matters.

Extend the existing closed Map inventory with operation receiver identity. Track
only guaranteed key coverage, not values, in the epoch/journal fact: one inclusive
contiguous interval. Straight-line known singleton adds establish/extend coverage;
merge only overlapping or adjacent ranges with overflow-safe adjacency, otherwise
keep one guaranteed range. There are no removals/aliases in the existing proof.
An ascending finite exact-start unit-step while with counter step LAST and an
unconditional top-level add keyed by that checked counter establishes
[start,limit-1] ONLY on normal exit. Never install future keys as a body invariant.
Empty/conditional/unknown/nested/step-first fills yield no new coverage.

A get is annotated only when its currently evaluated Int key interval is contained
in current guaranteed coverage. Add a compiler-only raw GetPresent helper using
mapaccess1, wrapped in the same ordinary Option[Int]{Some:true,Val:...}; canonical
Optional.get can then simplify in Go. All receiver/argument/default plumbing and
source positions remain ordinary; unknown keys keep None/missing faults. Debug,
custom evidence/dispatch and every excluded storage shape keep existing lowering.
No map value bounds, aggregate operations, source API or representation change.

For useful strict read loops, body-entry counter facts may exclude the terminal
limit, while summary delta analysis still uses the wider pre/post interval.
Assignments then update the facts in written order, so post-step key==limit is
not proven present. This refinement must be paired with before/after-step,
conditional holes, partial fills, empty/negative/Max bounds, nested/unknown flow,
missing Optional faults, key effects and allocation/runtime/standalone tests.
Independent reviewer must approve before implementation. Alternatives: leave the
~1.4x gap; globally assume presence (wrong); full relational map/value analysis
(unnecessary scope). Coverage inventory and transfer must stay linear.

## Canonical Go counter-post experiment

**Outcome:** Rejected, not implemented. Moving ten counter steps to post clauses gave no meaningful generic improvement and did not remove the remaining gaps.

After numeric proofs, generic accumulation has identical native instructions in
before/after multiplication callback builds, but relocating the hot loop changes
~0.34 to~0.64ns. Do not tune arbitrary padding or choose lucky placements. A
smaller compiler improvement worth controlling is canonical Go `for` post syntax:
for already-proved finite strict unit-step while loops whose unique counter step
is the last unconditional statement, lower that same step as Go's post clause.
No continue/break/return/nested/hidden writes are admitted by this existing proof.
Counter value before each body and poll, normal exit and cancellation are identical.
Keep source checks and body untouched; Debug retains its existing statements.
The step cannot fault under the existing proof. Its removed source marker must
not leave a stale label; calls/polls in the body retain their original markers.

First measure a generated-Go-only control across all ten programs; do not build
compiler selection without a meaningful gain. Alternatives: do nothing (Go SSA
may already produce identical code), padding/link layout tuning (not justified),
special Go flags or a looser polling phase (rejected). Independent review required.

## Extending chunks to two already-total loop bodies

**Outcome:** Rejected, not implemented. Generic improved0.60→0.32ns, but try0.80→1.15, length0.33→0.67 and list0.44→0.64 regressed in the whole program. No broader recognizer ships.

Canonical post clauses and polling-only outlining were measured and rejected:
selected gains came with regressions in other small loops. The existing constant
stride chunk removes the hot predicate, but generic accumulation still has one
per iteration. A narrow extension can use the SAME finite-loop and safe-prefix
proof, with no new value facts: permit the delta to read the induction counter,
and permit an exact source identity call whose sole body returns its immutable
parameter (already recognized by the numeric proof). Require Int checked types,
no defaults/conversion metadata, pure arguments and arithmetic already in safeInt;
no other calls/unary operations or carry references. Every original update still
runs in written order, individually, including the original identity call. No
aggregate formula, changed query phase or changed failure behavior is introduced.

Also permit one discarded call already selected by the closed single-field
record proof as the first statement, with a pure constant independent argument,
then the unique counter step last. The selected call is exactly one nonfaulting
field update; keep every original native update and its source marker. No general
method or arbitrary pointer mutation is admitted. Counter/cell peers and unknown
bounds retain ordinary polling. Debug stays unchanged.

Before implementation, measure a generated-Go chunk control for precisely generic
accumulation and proved record update on top of the existing length chunk. Require
independent review, actual native query-state observers for variable delta and
record cells, negative/Min/Max starts, partial chunks, cancellation and cleanup.
Do nothing remains preferable without broader stable performance. This extends
only the existing total-body recognizer; it adds no new proof dataflow or runtime API.


## Other rejected controls

Existing PollIndex(ctx,63) outlining at only generic or all numeric loop query
sites changed which tiny loops won, but materially regressed method/try/length
or traversal. No new cancellation helper, annotation, query policy or global
outlining ships. Removing the multiplication callback improved a relocated generic
loop while regressing method/try/length/traversal and matching; retain the narrower
checked callback. Assembly confirms unchanged generic instructions shifted by32
bytes across variants. No arbitrary padding or placement tuning was attempted.

All66 library counts/checksums pass. Focused controls repeat each suspect operation
20times in each of15 balanced processes rather than relying on one collection
phase: string.upper, map.string_put_get, regex.find_all and archive.tar_pack ratios
are0.966,1.027,1.003,1.028. These do not reproduce the larger full-suite slowdowns;
both datasets remain archived. Compiler proof allocation counts roughly double;
CPU profiles attribute excess timing growth in large checked graphs to collector
scanning (about28% cumulative), with memoized visits and no repeated subtree scan.

## Final inventory lookup complexity correction

Source inspection found that Program.ResolveMethods scans all implementations.
Calling explicit(Int,hash/equals) for each fresh map makes the new inventory
O(map constructors × unrelated methods), despite linear AST visits. Cache the
same two Int evidence decisions once per program after local-implementation
classification; when any local implementation exists the entire inventory already
falls back. With no local implementations primitive Int evidence is independent
of callable substitution/module. This preserves the exact evidence checks while
making their cost O(methods) once. A read-only immutable shared Bool avoids locks.

The record recognizer can also invoke resolveMethod for a concrete record inside
a generic caller. Narrow record eligibility to callers without substitution so
it never adds such repeated re-resolution. Generic callers retain ordinary calls;
the general lowerer still resolves them normally. Add accepted generic-caller
fallback and proof-only N/2N/4N mixed-map/unrelated-method controls. Alternatives:
keep the scan (violates the pass complexity rule), globally refactor the checker
method index (out of scope), remove evidence checks (unnecessary). This is a
conservative eligibility/lookup change; no generated code should change for the
measured programs. Compare final native hashes after rebuilding.

Outcome: retained after independent skeptical review. Compiler/lower tests pass;
128/256/512 candidate maps alongside as many unrelated methods take median
0.138/0.290/0.568 ms, with 196/334/600 allocations. Both complete native benchmark
executables rebuild byte-identically to the measured versions. An attempted
inherited-Int-default fixture was invalid: interface defaults require Optional.none;
the accepted explicit Int-default fallback remains covered by the method-shape test.
