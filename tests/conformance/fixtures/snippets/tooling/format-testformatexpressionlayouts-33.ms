// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:271 TestFormatExpressionLayouts
fn work() Int {
	if active and allowed and remaining > 0 { return 1 }
	return 0
}
// expect-error: MS2001 5:8 unknown binding active; declare it with 'active := ...' before use, define 'fn active(...) T { ... }', or import it from a module
// expect-error: MS2001 5:19 unknown binding allowed; declare it with 'allowed := ...' before use, define 'fn allowed(...) T { ... }', or import it from a module
// expect-error: MS2001 5:31 unknown binding remaining; declare it with 'remaining := ...' before use, define 'fn remaining(...) T { ... }', or import it from a module
