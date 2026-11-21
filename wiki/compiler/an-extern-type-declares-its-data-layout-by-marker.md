# An extern type declares its plain-data layout with `// ms: fields`

`Decimal` is an `extern type` the runtime passes as three words (`msstd_decimal_*` take `*const DecType`). The
declaration says so: `// ms: fields lo hi exp` above `export extern type Decimal` in `stdlib/math/decimal.ms`.

- C lowering (`lx_type`) reads it with `ms_doc_marker_args` and makes a MIR record with one integer field per
  name; an extern type without the marker stays a runtime object. No type name appears in C.
- The Rust checker and lowering ignore the line (only `// ms: data` and `clonable` are read) and keep their own
  `Decimal { lo, hi, exp }` record, so the two layouts must agree by hand until the Rust lowering is deleted.
- A record declaration (`export type Decimal: lo: Int ...`) was tried first and breaks the Rust checker: it looks
  `Decimal` up as a standard native type for number literals (`standard type Decimal` panic).
- Not `// ms: words`: that marker already means status wording (`crates/ms-lower/build.rs`).
