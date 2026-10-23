# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:36 TestRecursiveDataAndFiniteTypeApplications
type A[T]:
    b: B[List[T]]

type B[U]:
    a: A[U]
