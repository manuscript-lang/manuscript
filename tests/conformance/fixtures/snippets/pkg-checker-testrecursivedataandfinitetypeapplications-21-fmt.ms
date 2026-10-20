# conform: tags=closures,formatter,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:38 TestRecursiveDataAndFiniteTypeApplications
type Grow[T]:
    next: fn(value: Grow[List[T]]) Unit
