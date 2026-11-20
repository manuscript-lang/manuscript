# The C ownership classifier learns closeable types from method rows

`ms_classifier_mark_methods` marks the receiver of every row that closes it (`Method::closes`: a
`Closeable` impl, or an inherent `close()` returning `Void!`; C inherent rows have contract
`MS_TY_NONE`, unlike Rust's synthesized `Type$methods`). Without it the walk classed every
closeable type as a plain move and silently skipped resource diagnostics, so the body checker
refused all such types.

- The body checker admits types that close; the walk reports a resource parameter passed as a
  `move` argument without being declared `move` (`own_require_declared_move`).
- The lowering declines resources (`lb_mir_alt`): its scopes drop, they do not close. Recording
  implicit closes is the remaining step before it can lower a function that holds one.
- An interface with `move fn close()` is a resource too: `declares_owned_close` reads the operation table (`check->methods`).

## Owned payloads in the lowering

- `lb_owns(ty)` is the one rule for "the holder releases this": a String, a function value or any
  MIR type `mir_needs_drop` says so for. Call results, `let`, `return` and `move` parameters go
  through it, not through String checks.
- A parameter is handed over when declared `move` or when the body moves it: the ownership pass
  exports that as `facts->param_consumed` (Rust's `move str` on `make(name: String)`); callers
  read the callee's `MM_MOVE` modes.
- Records may hold Strings (a record made of those is owned); a record that closes is classed a
  resource by `lb_mir_ty`, so every construction goes through `lb_mir_ty`, not `lr_type`.
- A field of an owned temporary is declined: Rust holds the temporary until the statement ends,
  C drops call temporaries right after the call.

- The closing operation's name is read from the `Closeable` declaration (`close_name`), never
  spelled in C.
- `some`/`ok`/`error` around a value that owns something wrap only a fresh value (concatenation,
  text, record built here); a borrowed one stays an `opt.view`, which the ownership pass does not
  decide yet, so the walk declines (`own_check_wrap`). `none` handed out is `opt.none_owned`.
- Taking an owned payload out (`if v := opt`, `?`) is still declined.
