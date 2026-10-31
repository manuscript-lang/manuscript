# conform: tags=formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:22 TestRecursiveDataAndFiniteTypeApplications
type A[T]:
    value: T
    b: B[T]?

type B[U]:
    a: A[U]
