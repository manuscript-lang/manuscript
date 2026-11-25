// conform: tags=testing,tier-core
// conform: phase=check
// A variable called `type` (a kind, a category) fails to parse. The message names the cause
// and the fix instead of "expected an expression".
fn describe(type String) String {
	return f"unknown kind '{type}'"
}
// expect-error: MS1000 6:29-6:33 expected an expression, found 'type'; 'type' is a reserved word and cannot be used as a name: pick another name for the variable, field or parameter ('{' at column 28 starts an interpolation in f"..." text; write \\{ and \\} for literal braces, or drop the f)
