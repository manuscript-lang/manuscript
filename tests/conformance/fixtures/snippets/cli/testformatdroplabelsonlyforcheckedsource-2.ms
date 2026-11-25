// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:464 TestFormatDropLabelsOnlyForCheckedSource
fn total(left Int) Int {
	return add(left: left)
}
// expect-error: MS2001 5:12 unknown binding add; declare it with 'add := ...' before use, define 'fn add(...) T { ... }', or import it from a module
