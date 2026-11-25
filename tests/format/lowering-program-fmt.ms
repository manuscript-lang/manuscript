// conform: tags=control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-collections,tier-stdlib
// conform: phase=parse
// conform: origin=bench/perf/lowering/program.ms

fn scalar(limit Int) Int {
	var total = 0
	for index in 0..limit {
		total += index
	}
	return total
}

fn add(left Int, right Int) Int => left + right

fn calls(limit Int) Int {
	var total = 0
	for index in 0..limit {
		total = add(total, index)
	}
	return total
}

fn items(values List[Int], limit Int) Int {
	var total = 0
	for index in 0..limit {
		total += values[index]
	}
	return total
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn scalar(limit Int) Int {
// expect-formatted: \tvar total = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\ttotal += index
// expect-formatted: \t}
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn add(left, right Int) Int => left + right
// expect-formatted:
// expect-formatted: fn calls(limit Int) Int {
// expect-formatted: \tvar total = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\ttotal = add(total, index)
// expect-formatted: \t}
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn items(values List[Int], limit Int) Int {
// expect-formatted: \tvar total = 0
// expect-formatted: \tfor index in 0..limit {
// expect-formatted: \t\ttotal += values[index]
// expect-formatted: \t}
// expect-formatted: \treturn total
// expect-formatted: }
