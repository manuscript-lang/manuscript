// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:338 TestDisjointImplementations
interface Read[T] {
	fn get() Int
}

type Pair[A, B] {
	left A
	right B
}

fn Pair[A, A].get() Int {
	return 1
}

fn Pair[A, List[A]].get() Int {
	return 2
}
// expect-error: MS3010 17:21 duplicate or overlapping implementation of get on Pair: another receiver form of the same type could match the same application
