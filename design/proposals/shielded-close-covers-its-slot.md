# A shielded close covers its slot across blocks (#3625)

## Summary

- A close that faults after its scope-end entry was discarded leaves the slot's value unreleased. The unwind pass covers that window with a drop (`cover_shielded_slots`), but only when the shield enter, the close call and the shield exit sit in one block; by the time the pass runs (after `optimize`) the scope-end close can span three.
- Proposed: find the window along unconditional branches, so the slot is covered for the whole close. No new convention: the rule in the issue already exists (the slot's cover while it sits in the slot, the caller after `take` until `put`); this makes the cover apply where it was meant to.
- Decision requested: none. No language or user-visible change.

## Status

Proposal, 2026-11-16, main at `286540104`. Implemented in the same PR. Skeptical review: build with changes (cause wording, repeat-block guard, more tests); done.

## Problem

Measured with the leak runtime (`ms-rt/stats`, `MS_RT_LIB`), one `Placement.Here` promise per fault:

```
type Marker:
	label: String

fn var Marker.close() Void!: error(Error("marker closed"))

fn at_scope_end(label: String) Void:
	markers := [Marker(label.clone()), Marker(label)]
	void markers.length()
```

- Before: one live block (the list buffer) after the fault. A pending fault and a closure capture of the same list leave none.
- Cause: `elaborate` emits the enter, the call and the exit in one block (`close_infallible`, `close_result`), but the function `unwind` sees has `shield_enter` in `b0`, `call close_parts` in `b1` and `shield_exit` in `b2`, joined by `br` (verified by printing its blocks). The pass that splits them is likely the inliner (`inline_at`); not isolated. `cover_shielded_slots` looks for the exit in the enter's block, finds none, and skips the call.
- The three fixtures the issue names (`borrowed-scalar-optional-get`, `implicit-close-shielded`, `list-incoming-resource-transfer`) pass the leak sweep today: `--cfg intrap` is gone and later fixes (#3739, #4062, #4066) closed them.

## Design

- `cover_shielded_slots` follows unconditional `br` edges from the enter (at most 8 blocks, never a block twice) until the matching exit; calls on that path that close a slot in place get the existing `CleanupPush` and discard.
- A window with a conditional branch between the enter and the exit is still skipped (tested). Keeping the window in one block would cover it too, but means keeping the inliner from splitting around a shield; not proposed until a program shows such a window.
- An entry counts as still registered unless its discard lies on the path between the push and the call; an entry pushed off the path still covers, as before. A path with no exit is left alone.
- A callee that can `take` from the slot is skipped as before (`takes_from_slot`), so the double free the issue describes (a close that moves a field out, then faults) is not reintroduced.
- The close of a list still faults at the first failing element: elements after it are dropped by the cover, not closed. Closing every element first is a separate behavior change and not proposed.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/unwind.rs` | window search across branches; per-block insertion | `covers_a_shielded_close_whose_window_spans_blocks` (fails without the change); a conditional window, a taking callee and two closes in one window |
| `tests/conformance/fixtures/e2e/accept` | `faulting-close-in-list-releases-buffer`: scope end, pending fault, closure capture | leak sweep (`CONFORM_LEAKS=1`) |
| `design/wiki/compiler/unwind-leaves-slot-values-to-an-active-scope-close.md` | note the cross-block window | none |

## Alternatives

- Run the cover before the inliner splits blocks, or keep the window in one block: covers conditional windows as well, but couples the inliner to the shield; the path walk needs neither.
- Do nothing: no user-visible bug, only a leak inside a faulting operation. Rejected: the leak sweep sees it, and the issue is open for it.
- Close every element before faulting (`close_at_deferred`) and leave the slot whole: also leaks at scope end without this change, and dropping the list in the fault block double frees the closure-captured case (measured: -1 live block).
- One ownership convention for every close path (the issue's direction): larger, touches `elaborate.rs` and lowering; this change needs none of it.
