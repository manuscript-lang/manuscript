[Wiki](../index.md) › [Compiler and build](index.md)

# A look is checked against its owner's block, not only at returns

Verified (2026-11-25, #6979): the borrow pass froze a look's owner and the return rules tied a returned look to a `hold` argument, but nothing stopped a look from being stored in a place that lives longer than its owner. `held = View(inner)` in a loop, `views.append(View(inner))` into an outer list, a `var` parameter that receives a look of a local, and an escaping closure that captures a look all passed `ms check` and read freed memory (valgrind: invalid read; the live-block count stayed zero).

`src/compiler/own/look_stores.c` records, per function, each block's end offset, each binding's uses and each store of a look (an assignment, or a `move` argument of a call that also changes a place). A store is rejected when the owner's block ends before a later use of the holder, on a later round of a loop that declares the owner anew, or when the holder is a parameter. A binding that only borrows another owner (`names := lists[i]`) stands for that owner. An escaping closure that captures a look is rejected in `check_lambda` (`moves.c`): a look has no copy to hand the closure.

Apply when: adding a way to store a value (a new collection method, a `move` parameter) or a new kind of look; test it with a holder declared outside the owner's block.
Evidence: `look-assigned-outside-owner-block`, `look-appended-outside-owner-block`, `look-stored-in-parameter-outlives-callee`, `look-captured-by-escaping-closure` and the accepting `look-stored-in-longer-lived-place` in `tests/snippets/authored/`.
Verify: with the check off, the first fixture's program reads freed memory under `MS_ALLOC_LIBC=1 valgrind` (see the counting-runtime page).
