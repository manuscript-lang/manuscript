[Wiki](../index.md) › [Compiler and build](index.md)

# Evaluation order: receivers and operands are captured before later calls

Verified: a plain local read is not ordered against a later call unless the lowering orders it. A right-hand `match` or an index expression can reassign the receiver or the left operand local, so the receiver and each operand must be captured in written order before the operation that uses them, and prerequisites stay inside their short-circuit, match, and loop regions. Hoisting them changes source behavior.


Apply when: removing bound-call wrappers or lowering expressions to direct operations.
Evidence: [evaluation order](../../documentation/contributing/compiler/lowering/evaluation-order.md), [receiver reassignment regression](../../tests/conformance/fixtures/e2e/accept/collection-call-order.ms), [operand order](../../tests/conformance/fixtures/e2e/accept/operand-order.ms).
Verify: a list receiver initially holding 7 still yields 7 when its index expression reassigns the local to a list holding 9.

Map counter fusion requires a stable key, not merely two references to the same local. A
mutable key can change between insertion-key capture and a later lookup; eliding its explicit
clone can also leave a borrowed String pointing at consumed storage. Keep the single-probe
path for literals and immutable keys the other operand does not reference; an immutable
key can still be consumed by that operand. A direct numeric-literal operand also permits a
mutable key because it cannot access that key. Otherwise use ordinary lowering. See
[key stability regressions](../../tests/e2e/testdata/accept/map-counter-key-stability.ms) and
[#2857](https://github.com/manuscript-lang/manuscript/issues/2857).

The fused key slot must also have the map's checked key representation. A plain key lifted
to Optional requires ordinary argument conversion, not a raw slot passed with an Optional
descriptor ([#2858](https://github.com/manuscript-lang/manuscript/issues/2858)).

The same owner-lifetime rule applies to borrowed-key `add` and `add_default`: an immutable
key's source must not be consumed by the value argument. Keep its explicit clone when that
argument references the key owner.

Only a checked native structural `clone` may be elided, never a source method that happens
to have the same name ([#2865](https://github.com/manuscript-lang/manuscript/issues/2865)).

An owned native argument held for a later `try` remains registered on early exit. After all
arguments succeed, restore ownership of that captured value before refreshing or consuming
arguments. Otherwise lowering can reread a moved source or silently copy an explicit clone
([#2866](https://github.com/manuscript-lang/manuscript/issues/2866)).
