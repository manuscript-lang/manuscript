# conform: tags=diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:22 TestRecursiveDataAndFiniteTypeApplications
type A[T]:
    value: T
    b: Optional[B[T]]
type B[U]:
    a: A[U]
