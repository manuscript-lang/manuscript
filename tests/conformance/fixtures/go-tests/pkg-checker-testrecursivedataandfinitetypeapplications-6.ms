# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:23 TestRecursiveDataAndFiniteTypeApplications
type A[T, U]:
    b: B[U, T]
type B[X, Y]:
    a: A[Y, X]
