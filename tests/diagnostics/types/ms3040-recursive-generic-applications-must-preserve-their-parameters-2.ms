// conform: tags=diagnostics
// conform: phase=check
type A[T] {
	b B[List[T]]
}

type B[U] {
	a A[U]
}
// expect-error: MS3040 8:5 recursive generic applications must preserve their parameters in B.a; keep the same type arguments in the same positions along a recursive cycle
// expect-error: MS3040 4:5 recursive generic applications must preserve their parameters in A.b; keep the same type arguments in the same positions along a recursive cycle
