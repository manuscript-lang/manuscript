// conform: tags=diagnostics
// conform: phase=check
type A[T]:
    value: T
    b: B[T]?
type B[U]:
    a: A[U]
