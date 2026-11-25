// conform: tags=diagnostics,mutation
// conform: phase=check
type Counter {
	count Int
}

fn Counter.bump() Void {
	self.count += 1
}
// expect-error: MS3000 8:10 cannot change `self.count`: this method does not change its receiver; write `fn var` in its declaration to allow that
// expect-fix: 7:4-7:4 "var "
