// conform: tags=control-flow,diagnostics,formatter,lists,mutation,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/control-flow/loops.md:12
fn sum(values List[Int]) Int {
	var total = 0
	for value in values {
		total += value
	}
	return total
}
// expect-exit: 0
