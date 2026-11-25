// conform: tags=control-flow,diagnostics,formatter,generics,interfaces,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/recursive_types_test.go:21 TestRecursiveTypesPreserveInitializationAndHashing
interface I[T] {
	fn f(x I[List[T]]) Int
}

type Box[T] {
	v T
}

fn Box[T].f(x I[List[T]]) Int {
	return 1
}

fn main() Void {
	b := Box[Int](v: 1)
	i := I[Int](value: b)
}
// expect-error: MS3000 18:10 I[Int] is an interface and cannot be constructed; a type whose methods match I[Int] passes wherever I[Int] is expected, so pass the value directly
// expect-error: MS3040 5:8 recursive generic applications must preserve their parameters in I.f; keep the same type arguments in the same positions along a recursive cycle
