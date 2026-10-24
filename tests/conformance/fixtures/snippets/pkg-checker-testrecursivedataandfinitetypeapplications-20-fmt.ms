# conform: tags=closures,formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:37 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: Callable[[], Grow[List[T]]]
