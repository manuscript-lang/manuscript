// conform: tags=closures,diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:99 TestInterfaceHintDoesNotRecommendInvalidImplementationReceivers
interface Shape {
	fn area() Int
}

fn f(value fn() Int) Shape => value
// expect-error: MS3001 8:31 expected Shape, found fn() Int (in the return value); use a concrete value implementing Shape
