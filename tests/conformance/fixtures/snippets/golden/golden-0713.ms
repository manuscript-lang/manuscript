// conform: tags=diagnostics
// conform: phase=check
type B[T] {
	a A[List[T]]
}

type A[T] {
	b B[T]
}

type C[T] {
	b B[T]
}
// expect-error: MS3040 8:5 recursive generic applications must preserve their parameters in A.b; keep the same type arguments in the same positions along a recursive cycle
// expect-error: MS3040 4:5 recursive generic applications must preserve their parameters in B.a; keep the same type arguments in the same positions along a recursive cycle
