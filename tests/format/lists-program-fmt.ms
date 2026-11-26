// conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,records,stdlib-collections,tier-stdlib
// conform: phase=parse
// conform: origin=bench/perf/lists/program.ms

fn build(count Int) List[Int] {
	var values List[Int] = []
	for i in 0..count {
		values.append(i * 7919 % 100003)
	}
	return values
}

fn index(values List[Int], count Int) Int {
	var total = 0
	for i in 0..count {
		total += values[i % values.length()]
	}
	return total
}

fn iterate(values List[Int]) Int {
	var total = values.sum()
	return total
}

type Total {
	value Int
}

fn callbacks(values List[Int]) Int {
	var total = Total(0)
	values.for_each(
		value => {
			total.value += value
		}
	)
	return total.value
}

fn sorted(values List[Int]) List[Int] {
	return values.sorted(compare)
}

fn compare(left Int, right Int) Int {
	if left < right { return -1 }
	if left > right { return 1 }

	return 0
}

export fn main() Int => return 0

fn callback_write(var values List[Int]) Int {
	var total = Total(0)

	(
		values.clone().for_each(
			value => {
				total.value += value
				if value == 0 {
					values.set(0, 7)
				} }
		)
	)

	return total.value
}
// expect-format: rewritten
// expect-formatted:
// expect-formatted: fn build(count Int) List[Int] {
// expect-formatted: \tvar values List[Int] = []
// expect-formatted: \tfor i in 0..count {
// expect-formatted: \t\tvalues.append(i * 7919 % 100003)
// expect-formatted: \t}
// expect-formatted: \treturn values
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn index(values List[Int], count Int) Int {
// expect-formatted: \tvar total = 0
// expect-formatted: \tfor i in 0..count {
// expect-formatted: \t\ttotal += values[i % values.length()]
// expect-formatted: \t}
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn iterate(values List[Int]) Int {
// expect-formatted: \tvar total = values.sum()
// expect-formatted: \treturn total
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Total {
// expect-formatted: \tvalue Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn callbacks(values List[Int]) Int {
// expect-formatted: \tvar total = Total(0)
// expect-formatted: \tvalues.for_each(
// expect-formatted: \t\tvalue => {
// expect-formatted: \t\t\ttotal.value += value
// expect-formatted: \t\t}
// expect-formatted: \t)
// expect-formatted: \treturn total.value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn sorted(values List[Int]) List[Int] {
// expect-formatted: \treturn values.sorted(compare)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn compare(left, right Int) Int {
// expect-formatted: \tif left < right { return -1 }
// expect-formatted: \tif left > right { return 1 }
// expect-formatted:
// expect-formatted: \treturn 0
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn main() Int => return 0
// expect-formatted:
// expect-formatted: fn callback_write(var values List[Int]) Int {
// expect-formatted: \tvar total = Total(0)
// expect-formatted:
// expect-formatted: \t(
// expect-formatted: \t\tvalues.clone().for_each(
// expect-formatted: \t\t\tvalue => {
// expect-formatted: \t\t\t\ttotal.value += value
// expect-formatted: \t\t\t\tif value == 0 {
// expect-formatted: \t\t\t\t\tvalues.set(0, 7)
// expect-formatted: \t\t\t\t} }
// expect-formatted: \t\t)
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \treturn total.value
// expect-formatted: }
