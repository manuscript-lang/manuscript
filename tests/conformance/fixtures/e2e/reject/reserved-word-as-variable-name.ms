// conform: tags=testing,tier-core
// conform: phase=check
// A variable called `ref` (a git ref, a reference) fails to parse. The message names the cause
// and the fix instead of "expected an expression".
fn describe(ref: String) String:
	return "unknown revision '{ref}'"
