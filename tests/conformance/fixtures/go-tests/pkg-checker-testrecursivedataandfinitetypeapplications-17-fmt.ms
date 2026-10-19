# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:34 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Grow[List[T]]
