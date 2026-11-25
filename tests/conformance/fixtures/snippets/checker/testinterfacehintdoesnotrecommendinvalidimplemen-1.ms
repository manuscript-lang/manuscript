// conform: tags=diagnostics,interfaces,tier-core
// conform: phase=check
// conform: origin=pkg/checker/interface_hints_test.go:96 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape {
	fn area() Int
}

fn f() Shape => 1
// expect-error: MS3001 8:17 expected Shape, found Int (in the return value); use a concrete value implementing Shape
