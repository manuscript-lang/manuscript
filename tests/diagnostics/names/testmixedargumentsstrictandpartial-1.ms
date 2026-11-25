// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/positional_arguments_test.go:12 TestMixedArgumentsStrictAndPartial
fn run() Int {
	return select[Int](1, last: 3, value => value + 1)
}
// expect-error: MS2001 5:12 unknown binding select; declare it with 'select := ...' before use, define 'fn select(...) T { ... }', or import it from a module
