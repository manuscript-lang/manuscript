// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/redundant_labels_test.go:63 TestDropRedundantLabelsSkipsBrokenSource
fn f(a Int) Int {
	return g(a: a)
}
// expect-error: MS2001 5:12 unknown binding g; declare it with 'g := ...' before use, define 'fn g(...) T { ... }', or import it from a module
