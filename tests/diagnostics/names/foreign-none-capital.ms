// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Int? {
	return None
}
// expect-error: MS2001 5:12 unknown binding None; Manuscript writes absence as null: a nullable `T?` is a `T` or null, and a present value is just the value, which converts where a nullable is expected
// expect-fix: 5:12-5:16 "null"
