# conform: tags=closures,diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:37 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Callable[[], Grow[List[T]]]
