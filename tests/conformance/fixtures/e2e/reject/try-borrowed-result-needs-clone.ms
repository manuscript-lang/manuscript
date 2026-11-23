// conform: tags=diagnostics,ownership,tier-core
// conform: phase=check
// `.clone()` is the only copy: `?` cannot move the error out of a borrowed Result, and it
// cannot move it out of a call whose result borrows a place either.
fn relay(value: String!String) String!String:
	text := value?
	return ok(text + "x")

fn pass(value: String!String) String!String:
	return value

fn again(value: String!String) String!String:
	text := pass(value)?
	return ok(text)

fn copied(value: String!String) String!String:
	text := value.clone()?
	return ok(text + "x")

fn aliased(value: String!String) String!String:
	alias := value
	text := alias?
	return ok(text)
