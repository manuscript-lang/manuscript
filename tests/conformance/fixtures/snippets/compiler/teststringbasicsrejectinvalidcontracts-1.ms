// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/string_basics_test.go:17 TestStringBasicsRejectInvalidContracts
fn wrong() Int {
	compare := "a".compare
	return compare(value: "b")
}
// expect-error: MS3004 6:20 unknown argument value; parameters of compare: other
// expect-error: MS3003 6:12 missing argument other: String in call to compare; add 'other: <String>'
