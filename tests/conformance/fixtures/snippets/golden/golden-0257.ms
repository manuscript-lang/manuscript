// conform: tags=diagnostics
// conform: phase=check
fn g(amount Int) Int {
	return amount
}

fn f() Int {
	return g(amunt: 1)
}
// expect-error: MS3004 8:14 unknown argument amunt; did you mean 'amount'?
// expect-fix: 8:14-8:19 "amount"
// expect-error: MS3003 8:12 missing argument amount: Int in call to g; add 'amount: <Int>'
