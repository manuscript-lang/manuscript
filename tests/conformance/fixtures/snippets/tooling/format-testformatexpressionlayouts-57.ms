// conform: tags=closures,control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_layout_test.go:415 TestFormatExpressionLayouts
fn work() Int {
	return apply(
		value: 3,
		transform: fn(value Int) Int {
			if value == 0 { return 0 } next := value + 1
			return next
		}
	)
}
// expect-error: MS2001 5:12 unknown binding apply; declare it with 'apply := ...' before use, define 'fn apply(...) T { ... }', or import it from a module
