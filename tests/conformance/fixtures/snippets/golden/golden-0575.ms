// conform: tags=diagnostics
// conform: phase=check
size := match 1 {
	n => {
		values.add(n, n)
		values.get(n).get()
	}
	null => values.length()
}
// expect-error: MS3070 3:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
