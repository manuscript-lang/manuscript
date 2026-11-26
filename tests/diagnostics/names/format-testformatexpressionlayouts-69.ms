// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:500 TestFormatExpressionLayouts
fn work() Int {
	if (
		tagged_detail(integer) != "integer 7"
		or tagged_detail(text) != "text diagnostic"
	) {
		return 1
	}
	return 0
}
// expect-error: MS2001 6:9 unknown binding tagged_detail; declare it with 'tagged_detail := ...' before use, define 'fn tagged_detail(...) T { ... }', or import it from a module
// expect-error: MS2001 7:12 unknown binding tagged_detail; declare it with 'tagged_detail := ...' before use, define 'fn tagged_detail(...) T { ... }', or import it from a module
