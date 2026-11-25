// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:26 TestDiagnosticsStateCauseAndFix
fn g(amount Int) Int {
	return amount
}

fn f() Int {
	return g(amunt: 1)
}
// expect-error: MS3004 9:14 unknown argument amunt; did you mean 'amount'?
// expect-fix: 9:14-9:19 "amount"
// expect-error: MS3003 9:12 missing argument amount: Int in call to g; add 'amount: <Int>'
