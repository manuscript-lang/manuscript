// conform: tags=diagnostics,parser,tier-core
// conform: phase=check
// conform: origin=foreign-syntax diagnostics
fn f() Void {
	a := none
}
// expect-error: MS2001 5:10 unknown binding none; Manuscript writes absence as null: a nullable `T?` is a `T` or null, and a present value is just the value, which converts where a nullable is expected
// expect-fix: 5:10-5:14 "null"
