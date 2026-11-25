// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/result_argument_inference_test.go:47 TestResultArgumentInference
fn first() Int {
	r Int! := f()
	return h(r)
}
// expect-error: MS2001 5:15 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
// expect-error: MS2001 6:12 unknown binding h; declare it with 'h := ...' before use, define 'fn h(...) T { ... }', or import it from a module
