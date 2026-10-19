# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:40 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Grow[Int]
