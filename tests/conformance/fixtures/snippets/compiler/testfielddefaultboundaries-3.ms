// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/field_defaults_test.go:13 TestFieldDefaultBoundaries
type Options {
	count Int = count
}
// expect-error: MS2001 5:17 unknown binding count; declare it with 'count := ...' before use, define 'fn count(...) T { ... }', or import it from a module
