# A borrowing native's result handed to a new owner is copied

`List.slice` lowers to `slice_view`: the Result's list borrows the source's elements (`cap` 0, never freed). Its MIR type is the ordinary `Result[List[T], E]` and the lowering owns it like any call result, so a consumer that takes ownership (`.get_or(..)` has a `move` receiver, a `for` over a temporary consumes it) saw an owner. Growing the view copied pointers, not elements, and a consuming loop freed the source's strings: heap corruption that surfaced as a hang at thread exit (#7108, #7116).

`fn_status_call` records the result of a `@borrows` native (`fn_is_native_view`), and `take_ownership` copies it (`fn_implicit_clone`) when the expression is consumed by move. Borrow uses (`?`, `match`, `for ... in x.slice(..)?`) stay copy-free. Fixture: `slice-result-moved-into-owner`.
