// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// `.clone()` is the only copy: `?` cannot move the error out of a borrowed Result, and it
// cannot move it out of a call whose result borrows a place either.
fn relay(value String!String) String!String {
	text := value?
	return ok(text + "x")
}

fn pass(hold value String!String) &String!String {
	return value
}

fn again(value String!String) String!String {
	text := pass(value)?
	return ok(text.clone())
}

fn copied(value String!String) String!String {
	text := value.clone()?
	return ok(text + "x")
}

fn aliased(value String!String) String!String {
	alias := value
	text := alias?
	return ok(text.clone())
}
// expect-error: MS3000 6:13 `value` is a borrow, so `?` cannot move its error out; write `value.clone()?` to relay a copy, or take it from an owner
// expect-error: MS3000 15:13 the result of `pass(..)` is a borrow of its arguments, so `?` cannot move its error out; write `pass(..).clone()?` to relay a copy, or take it from an owner
// expect-error: MS3000 26:13 `alias` is a borrow, so `?` cannot move its error out; write `alias.clone()?` to relay a copy, or take it from an owner
