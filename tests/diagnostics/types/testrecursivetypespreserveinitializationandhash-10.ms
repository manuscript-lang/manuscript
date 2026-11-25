// conform: tags=diagnostics,formatter,lists,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/recursive_types_test.go:19 TestRecursiveTypesPreserveInitializationAndHashing
type B[T] {
	a A[List[T]]
}

type A[T] {
	b B[T]
}

type C[T] {
	b B[T]
}
// expect-error: MS3040 9:5 recursive generic applications must preserve their parameters in A.b; keep the same type arguments in the same positions along a recursive cycle
// expect-error: MS3040 5:5 recursive generic applications must preserve their parameters in B.a; keep the same type arguments in the same positions along a recursive cycle
