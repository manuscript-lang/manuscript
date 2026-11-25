// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/performance_test.go:31 performanceProject
export fn main() Int {
	result := f_0_0(1)
	return result
}
// expect-error: MS2001 5:15 unknown binding f_0_0; declare it with 'f_0_0 := ...' before use, define 'fn f_0_0(...) T { ... }', or import it from a module
