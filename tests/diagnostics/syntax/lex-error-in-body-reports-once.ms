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
// expect-error: MS1000 7:11-7:15 invalid number 0o17; octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)
// expect-error: MS1000 12:13-12:14 unexpected source character '$'; this character is not part of Manuscript's syntax outside text
