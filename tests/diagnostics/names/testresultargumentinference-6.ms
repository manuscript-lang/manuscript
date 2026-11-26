// conform: tags=alternatives,diagnostics,formatter,generics,records,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:76 TestResultArgumentInference
enum Wrapped[T] {
	value(r T!)
}

fn first() Wrapped[Int] => Wrapped.value(f())
// expect-error: MS2001 8:42 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
