# conform: tags=formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:35 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: List[Grow[List[T]]]
