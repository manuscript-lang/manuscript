// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:318 TestFormatExpressionLayouts
fn work() Bool {
	return active or allowed and remaining > 0
}
// expect-error: MS2001 5:12 unknown binding active; declare it with 'active := ...' before use, define 'fn active(...) T { ... }', or import it from a module
// expect-error: MS2001 5:22 unknown binding allowed; declare it with 'allowed := ...' before use, define 'fn allowed(...) T { ... }', or import it from a module
// expect-error: MS2001 5:34 unknown binding remaining; declare it with 'remaining := ...' before use, define 'fn remaining(...) T { ... }', or import it from a module
