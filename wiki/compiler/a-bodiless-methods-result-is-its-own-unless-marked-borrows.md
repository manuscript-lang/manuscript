# A bodiless method's result is its own unless its declaration says `// ms: borrows`

The C ownership walk has no body to walk for a runtime or `...` method, so it reads the declaration: what the
method takes is what its signature says (`move`, `var`), and its result is an owned value unless a
`// ms: borrows` line sits above it (`own_method_lends`). The marker replaces Rust's `native_borrow` name list for
`List.get`, `List.slice` (always, though Rust lends only scalar slices), `Map.get`, `Map.keys`, `Map.values`,
`Optional.get`, `Result.get` and `Bytes.view`.

- A marked call is left to Rust by the walk, the same as before; mark a method only when its result points into the
  receiver. A wrongly missing marker lets the walk treat a borrow as owned (a double drop or a missed conflict).
- Rust ignores the line (only `data` and `clonable` are read), so the stdlib stays shared.
- Lowering a native found-flag call (`-> u8` with an out String or list, `Bytes.decode_utf8`) builds the Optional like
  Rust does; it was never reached before because the walk declined every such method.
