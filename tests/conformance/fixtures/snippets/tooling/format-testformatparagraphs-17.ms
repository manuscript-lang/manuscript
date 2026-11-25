// conform: tags=control-flow,diagnostics,formatter,interpolation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:254 TestFormatParagraphs
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
// expect-error: MS2001 4:24 unknown binding choose; declare it with 'choose := ...' before use, define 'fn choose(...) T { ... }', or import it from a module
// expect-error: MS2001 6:13 unknown binding choose; declare it with 'choose := ...' before use, define 'fn choose(...) T { ... }', or import it from a module
