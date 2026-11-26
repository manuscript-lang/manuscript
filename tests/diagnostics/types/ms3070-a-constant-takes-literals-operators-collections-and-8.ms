// conform: tags=diagnostics
// conform: phase=check
callback := fn(value Bool) {
	if value { return 1 }
	return "wrong"
}
// expect-error: MS3070 3:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
