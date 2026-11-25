// conform: tags=diagnostics
// conform: phase=check
transform := fn(item Int) Int {
	return item
	apply(transform)
}
// expect-error: MS3070 3:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
