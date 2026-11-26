// conform: tags=diagnostics
// conform: phase=check
fn bump(by Int) Int {
	self.total += by + 1
	return self.total
}
// expect-error: MS3000 4:10 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
