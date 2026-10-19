# conform: tags=closures,diagnostics,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:38 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: fn(value: Grow[List[T]]) Unit
