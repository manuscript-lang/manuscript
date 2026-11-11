// conform: tags=diagnostics
// conform: phase=check
type A[T, U]:
    b: B[U, T]
type B[X, Y]:
    a: A[Y, X]
