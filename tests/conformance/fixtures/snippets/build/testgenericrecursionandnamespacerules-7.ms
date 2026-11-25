// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:262 TestGenericRecursionAndNamespaceRules
interface Read[T] {
	fn get() T
}

type Box[T] {
	value T
}

fn Box[T].get() T {
	return self.value
}

fn Box[Int].get() Int {
	return self.value
}
// expect-error: MS3010 16:13 duplicate or overlapping implementation of get on Box: another receiver form of the same type could match the same application
