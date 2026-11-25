# Lowering tables grow; a fixed cap silently turns a view into a copy

`LowerFn` kept the borrowing variants of calls (`viewed`) and the results of `@borrows` natives (`native_views`) in arrays of 8, and dropped later entries without a word. A function with a ninth `common_result(..)?` then no longer saw those calls as views and copied every payload: `make copy-check` listed 13 hidden copies in one fixture. Both tables now grow in the module arena (`fn_grow`). Do not add a fixed-size side table to `LowerFn`; a table that can overflow must grow or fail loudly.

A `?` in an operand position (`common_result(..)? == x`, `(f(..)?).size`) takes the temporary an answering call hands on (`fn_take_from_temporary`) and the statement's scope owns it, so the error leaves with the error taken, not copied.
