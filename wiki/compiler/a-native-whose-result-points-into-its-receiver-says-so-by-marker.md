# A native whose result points into its receiver says so with `// ms: borrows`

`String.chars`, `lines`, `split`, `view` and `view_bytes` in `stdlib/core/intrinsics.ms` carry
`// ms: borrows` (`ms_doc_has_marker`); the checker reads it into `Target.borrows` and records
`call_borrows[call]`, instead of matching method names as the Rust `native_borrow` does.

- The C checker claims such a call only where the result is used in place: the iterable of a `for`, or
  the receiver of another primitive operation (`s.view(a, b).clone()`), on a receiver that is a local.
  A bound, passed or returned result leaves the function to Rust.
- The ownership walk (`own_borrowed_call`) treats the result like a borrowed local list: the receiver
  stays unchanged for the whole loop.
- Lowering declines these calls (`call_borrows`): Rust uses borrowing twins (`string_view` with a slot)
  and scans `for c in s.chars()` without building a list, and C must match that MIR before it lowers them.
