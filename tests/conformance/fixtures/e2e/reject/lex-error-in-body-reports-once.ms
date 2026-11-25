// conform: tags=lexer,parser,diagnostics,tier-core
// conform: phase=check
// A lexical error inside a body is reported once: the closing brace after it is not an unmatched delimiter,
// and the next function's error is still found.
fn first() Void {
	print(1)
	print(0o17)
	print(2)
}

fn second() Void {
	x := (1 $)
}
