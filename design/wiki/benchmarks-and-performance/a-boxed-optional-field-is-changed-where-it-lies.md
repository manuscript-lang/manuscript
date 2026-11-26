[Wiki](../index.md) › [Benchmarks and performance](index.md) › A boxed optional field is changed where it lies

# A boxed optional field is changed where it lies

`self.left?.insert(key)` on a recursive record (`left Node?`) used to take the whole record out of `self`, move the child out of its box (freeing the block), copy it into a slot, call, then allocate a new block for the child and store the record back. Every level of a tree insert paid one `free` and one `alloc` (8.6M pairs in the `objgraph` suite program, which ran 1.56x of Rust). A boxed optional is the pointer to its payload block, so `fn_try_var_slot` now loads the field in place, returns when it is absent, and lends the block itself (`opt.addr`) as the callee's `var` slot; nothing is taken, unboxed, freed or put back. `objgraph` went from 2,383M to 958M instructions and 583 to 333 ms.

Two conditions gate it: the optional is boxed (`mir_ty_opt_boxed`; an inline optional keeps the take and put-back path) and the field's address is known (`fn_field_address`, which needs `field_cell_exact`: a boxed optional is one pointer leaf, so it no longer blocks the fields after it). Guard: `tests/lang/stdlib/optional-field-chain-in-place.ms`.

Method: callgrind showed `msrt_alloc` called 12.6M times against 6.6M expected nodes; `ms build --emit mir --opt` of `insert` showed the take, unbox, slot, re-box sequence.
