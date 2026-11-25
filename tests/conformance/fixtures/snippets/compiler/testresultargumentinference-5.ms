// conform: tags=diagnostics,formatter,generics,records,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/compiler/result_argument_inference_test.go:73 TestResultArgumentInference
type Holder[T] {
	r T!
}

fn first() Holder[Int] => Holder(f())
// expect-error: MS2001 8:34 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
