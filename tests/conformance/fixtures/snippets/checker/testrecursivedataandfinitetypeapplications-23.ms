# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:40 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Grow[Int]
