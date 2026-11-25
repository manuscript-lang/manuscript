// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/member_cascade_test.go:16 TestUnknownMemberReportsOnce
fn f[T](a T) T {
	return a.foo()
}
// expect-error: MS2001 5:14 unknown or ambiguous member foo on T; T has no bound, so it has no operations: bound it where it is declared, as in `fn f[T: Contract]` for a function or `fn var Repository[T: Contract].add` for a method of a generic type
