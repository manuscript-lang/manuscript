[Wiki](../index.md) › [Language](index.md)

# `String.split`, `lines` and `chars` lend their receiver

Decision (Chinmay, 2026-11-12, "yeah" to track 2 of [c-parity-structure](../../proposals/c-parity-structure.md); follows [String.view is an explicit borrow](string-view-is-an-explicit-borrow-slice-stays-a-copy.md)): the results of `split`, `lines` and `chars` on a `String` are borrows of the receiver, under the `view` rules. Keeping one (a field, a return, a `var` binding, an escaping closure) needs `.clone()`; the receiver cannot change while the result is used. A loop variable over the result borrows its piece, so collecting pieces is `out.append(piece.clone())`.

Verified: the checker rule is the existing `native_borrow_receiver` and `view` error path in `ms-check/src/ownership/walk` with the three names added; only a `String` receiver that is a place lends (a temporary receiver keeps the copying call). Lowering reads the `BorrowedRead` fact and uses `msrt_string_split_view`, so `f := line.split(" ")` then `f[5]` no longer copies the pieces. `chars` and `lines` still build their list; their element strings are copied only when non-ASCII, and a lent `chars`/`lines` result is not yet a view entry.

Migration found 15 `.clone()` sites in the standard library and 11 conformance fixtures (closure captures of a loop variable, a `var` binding of `chars()`, `append(piece)`, returning a piece, mutating the receiver inside the loop). 

Apply when: extending lending to another method, add its name to `native_borrow_receiver` and the `view` error in `calls.rs`, give it a view entry in lowering, and add accept and reject fixtures next to [lent-split-keep-rejected](../../tests/conformance/fixtures/snippets/authored/lent-split-keep-rejected.ms).

## Extended to `Map.keys`, `Map.values` and `List.slice`

Same rule and checker path (`native_borrow_receiver`, the `view` error in `calls.rs`; `xs.slice(a, b).get()` gets its own `get` check because the payload of the lent `Result` is the lent slice). Lowering: `msrt_map_keys_view` and `msrt_map_values_view` (string payloads become views, other payloads copy as before), and `msrt_list_slice_view`, which returns a `cap == 0` list pointing into the receiver. A `cap == 0` list is never freed or dropped: the list drop glue in `ms-clif` (`glue_drop`) and `drop_list` in `ms-rt` skip it. All four entries carry `ExternRole::ViewResult`, and `copyelim` taints the out slot of such a call, because a `Result` slice reads its list back from the slot and a `.clone()` of it was being turned into a move that shared the receiver's storage (`primitive-list-storage` caught it). `Map.entries` stays a copy: its records are built inline, and a record list of views has no role for `copyelim` to see.

Evidence: slice windows 124.5M to 103.0M instructions (the rest is the checked sum loop). Migration: 2 stdlib sites (`SortedMap.split`), 4 fixtures. Fixtures: [lent-collection-views](../../tests/conformance/fixtures/snippets/authored/lent-collection-views.ms), [lent-collection-keep-rejected](../../tests/conformance/fixtures/snippets/authored/lent-collection-keep-rejected.ms).
