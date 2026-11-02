# conform: tags=diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:35 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: List[Grow[List[T]]]
