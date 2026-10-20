# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:42 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Bridge
type Bridge:
    next: Grow[Int]
