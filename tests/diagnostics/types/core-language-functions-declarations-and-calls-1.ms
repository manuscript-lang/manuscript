// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:10
fn decrement(value Int) Int {
	return value - 1
}

remaining := decrement(3)
// expect-error: MS3070 8:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
