// conform: tags=control-flow,diagnostics,lists,mutation,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:86
fn sum(values List[Int]) Int {
	var total = 0
	for value in values {
		total += value
	}
	return total
}

total := sum([1, 2, 3])
empty := sum([])
// expect-error: MS3070 12:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 13:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
