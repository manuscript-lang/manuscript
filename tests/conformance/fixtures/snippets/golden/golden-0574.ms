// conform: tags=diagnostics
// conform: phase=check
callback := fn() Int {
	values := Map[Int, Int]()

	child := fn() Int {
		grandchild := fn() Int => values.length()
		return grandchild()
	}

	return child()
}
// expect-error: MS3070 3:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
