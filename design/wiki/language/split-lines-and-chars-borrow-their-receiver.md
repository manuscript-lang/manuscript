[Wiki](../index.md) › [Language](index.md)

# `String.split`, `lines` and `chars` borrow their receiver

Decision (Chinmay, 2026-11-12, "yeah" to track 2 of [c-parity-structure](../../proposals/c-parity-structure.md); follows [String.view is an explicit borrow](string-view-is-an-explicit-borrow-slice-stays-a-copy.md)): the results of `split`, `lines` and `chars` on a `String` are borrows of the receiver, under the `view` rules. Keeping one (a field, a return, a `var` binding, an escaping closure) needs `.clone()`; the receiver cannot change while the result is used. A loop variable over the result borrows its piece, so collecting pieces is `out.append(piece.clone())`.

Verified: the checker rule is the existing native-borrow and `view` error path of the checker (`@borrows` on the declaration, `src/compiler/own/result_borrows.c`, `src/compiler/check/calls.c`) with the three names added; only a `String` receiver that is a place borrows (a temporary receiver keeps the copying call). Lowering reads the `BorrowedRead` fact and uses `msrt_string_split_view`, so `f := line.split(" ")` then `f[5]` no longer copies the pieces. `split`, `lines` and `fields_by` are now lazy look records (see [lazy-text-iterators-are-look-records-in-ms](../benchmarks-and-performance/lazy-text-iterators-are-look-records-in-ms.md)); `chars` still builds its list.

Migration found 15 `.clone()` sites in the standard library and 11 conformance fixtures (closure captures of a loop variable, a `var` binding of `chars()`, `append(piece)`, returning a piece, mutating the receiver inside the loop). 

Apply when: extending borrowing to another method, mark its declaration `@borrows` and cover the `view` error in `calls.c`, give it a view entry in lowering, and add accept and reject fixtures next to borrowed-split-keep-rejected.

## Extended to `Map.keys`, `Map.values` and `List.slice`

Same rule and checker path (`@borrows`, the `view` error in `check/calls.c`; `xs.slice(a, b).get()` gets its own `get` check because the payload of the borrowed `Result` is the borrowed slice). Lowering: `msrt_map_keys_view` and `msrt_map_values_view` (string payloads become views, other payloads copy as before), and `msrt_list_slice_view`, which returns a `cap == 0` list pointing into the receiver. A `cap == 0` list is never freed or dropped: the list drop glue (`mir_glue_drop.c`) and the runtime list drop (`src/runtime/core/list.c`) skip it. All four entries carry `ExternRole::ViewResult`, and `copyelim` taints the out slot of such a call, because a `Result` slice reads its list back from the slot and a `.clone()` of it was being turned into a move that shared the receiver's storage (`primitive-list-storage` caught it). `Map.entries` stays a copy: its records are built inline, and a record list of views has no role for `copyelim` to see.

Evidence: slice windows 124.5M to 103.0M instructions (the rest is the checked sum loop). Migration: 2 stdlib sites (`SortedMap.split`), 4 fixtures. Fixtures: borrowed-collection-views, borrowed-collection-keep-rejected.

A borrowed slice is iterated by `for`, which ends with `list.release` on the list. `list.release` must skip a view (`cap == 0`) like `glue_drop`; it freed `ptr + offset` until a bench test crashed. A `for` over a slice also moves each element out and drops it, so a slice of heap-owning elements (`List[String]`) freed what the receiver still held; only slices of elements that own nothing (numbers, `Bool`) are borrowed, in the checker (`native_borrow_receiver`) and in lowering (`needs_drop`). Fixtures with inline (≤15 byte) strings hide both bugs: test with long strings and run the built binary under valgrind.

## Lowering picks the borrowing form from a declaration, not a name

(2026-11-16, [declared-view-twins](../../proposals/declared-view-twins.md).) The runtime function that is the borrowing form of a native declares it in its `// ms:` comment (`view_of=`, `shared_view_of=`, `first_of=`, `iter_of=`, base symbol as the value) and a parameter typed `*mut FrameBuf<T, N>` gets a frame slot. Lowering never tests a method name for this; to borrow another native, add the flag and the entry. Guard counts before and after were equal (`guard-splitfirst`, `guard-splitbuf`). A set shares its map's entry points but never their views.
