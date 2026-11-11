// conform: tags=diagnostics
// conform: phase=check
type B[T]:
    a: A[List[T]]
type A[T]:
    b: B[T]
type C[T]:
    b: B[T]
