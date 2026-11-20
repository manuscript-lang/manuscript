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
