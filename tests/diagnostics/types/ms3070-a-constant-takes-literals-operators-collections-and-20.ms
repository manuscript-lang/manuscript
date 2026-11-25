// conform: tags=diagnostics
// conform: phase=check
callback := fn() Int {
	values := Map[Int, Int]()
	values.add(1, 2)
	return values.get(1).get()
}
// expect-error: MS3070 3:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
