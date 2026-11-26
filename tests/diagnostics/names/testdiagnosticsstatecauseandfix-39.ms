// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:58 TestDiagnosticsStateCauseAndFix
fn f() Int {
	n := "abc".foo()
	return 0
}
// expect-error: MS2001 5:16 unknown or ambiguous member foo on String; available starting with 'f': fields, fields_by, find_char; 57 members in total
