// conform: tags=diagnostics
// conform: phase=check
fn example(value Int = choose(first: 1, second: 2)) Int {
	text := f"# if value: return {value}"
	next := choose(
		first: value,
		// Explain this argument.
		second: 2
	)
	if (next > 0 and value > 0) { return next }

	return 0
}
// expect-error: MS2001 3:24 unknown binding choose; declare it with 'choose := ...' before use, define 'fn choose(...) T { ... }', or import it from a module
// expect-error: MS2001 5:13 unknown binding choose; declare it with 'choose := ...' before use, define 'fn choose(...) T { ... }', or import it from a module
