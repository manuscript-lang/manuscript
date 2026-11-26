// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:194 TestCompilerPublicAPIs
fn value() Int {
	return missing
}
// expect-error: MS2001 5:12 unknown binding missing; declare it with 'missing := ...' before use, define 'fn missing(...) T { ... }', or import it from a module
