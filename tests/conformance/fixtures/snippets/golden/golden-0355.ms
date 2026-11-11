// conform: tags=diagnostics
// conform: phase=check
type A[T]:
    b: B[List[T]]
type B[U]:
    a: A[U]
