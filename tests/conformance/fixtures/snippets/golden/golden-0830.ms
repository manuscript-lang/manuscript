// conform: tags=diagnostics
// conform: phase=check
type Counter {
	value Int
}

fn advance(counter Counter) Int {
	counter.value += 1
	return counter.value
}

fn work(counter Counter) List[Int] {
	var value = 1
	return [
		value,
		counter.value,
		counter.value,
		advance(counter),
		value,
		match 2 {
			number => {
				value = number
				advance(counter)
			} null => 0
		},
		value,
		counter.value,
		advance(counter),
	]
}
// expect-error: MS3070 21:13 a match on Int takes literal arms such as 1, "text" or true, and a final '_ => ...' arm; to bind or compare computed values use if/else
// expect-error: MS3070 21:13 a literal arm has no payload to bind
// expect-error: MS2001 22:25 unknown binding number; declare it with 'number := ...' before use, define 'fn number(...) T { ... }', or import it from a module
// expect-error: MS3070 24:15 a match on Int takes literal arms such as 1, "text" or true, and a final '_ => ...' arm; to bind or compare computed values use if/else
// expect-error: MS3050 20:9 non-exhaustive match on Int; add a final '_ => ...' arm
