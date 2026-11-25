// conform: tags=diagnostics,interpolation,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_test.go:190 TestFormatMapAndShorthand
fn f() Void {
	values := {"a": 1, "b": {1: 2}}
	consume(values, other: {})
}
// expect-error: MS3001 5:29 expected Int, found Map[Int, Int] (in entry 4 of the literal, whose entries share one type)
// expect-error: MS2001 6:5 unknown binding consume; declare it with 'consume := ...' before use, define 'fn consume(...) T { ... }', or import it from a module
