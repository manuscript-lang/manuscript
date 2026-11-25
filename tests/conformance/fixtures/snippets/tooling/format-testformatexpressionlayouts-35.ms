// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/format/format_layout_test.go:283 TestFormatExpressionLayouts
fn work() Int {
	var total = 1
	total += 2
	total *= 3
	box.count -= total
	return total
}
// expect-error: MS2001 8:5 unknown binding box; declare it with 'box := ...' before use, define 'fn box(...) T { ... }', or import it from a module
// expect-error: MS3000 8:9 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
