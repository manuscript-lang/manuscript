// conform: tags=testing,tier-core
// conform: phase=check
// A variable called `type` (a kind, a category) fails to parse. The message names the cause
// and the fix instead of "expected an expression".
fn describe(type String) String {
	return f"unknown kind '{type}'"
}
