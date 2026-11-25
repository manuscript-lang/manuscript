// conform: tags=diagnostics,formatter,generics,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:98 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape {
	fn area() Int
}

fn f[T](value T) Shape => value
// expect-error: MS3001 8:27 expected Shape, found T (in the return value); use a concrete value implementing Shape
