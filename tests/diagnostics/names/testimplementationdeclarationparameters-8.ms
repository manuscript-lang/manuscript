// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:549 TestImplementationDeclarationParameters
interface Same[V Equal] {
	fn same(other V) Bool
}

type Box[T] {
	value T
}

fn Box[T Equal].same(other T) Bool {
	return self.value == other
}

fn compare[T](value Box[T], other T) Bool {
	return value.same(other: other)
}
// expect-error: MS2001 17:18 unknown or ambiguous member same on Box[T]; same requires T to be Equal; declare T: Equal on the enclosing function
