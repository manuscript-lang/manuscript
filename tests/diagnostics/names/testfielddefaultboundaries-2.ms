// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/field_defaults_test.go:12 TestFieldDefaultBoundaries
type Options {
	first Int = second
	second Int = 2
}
// expect-error: MS2001 5:17 unknown binding second; declare it with 'second := ...' before use, define 'fn second(...) T { ... }', or import it from a module
