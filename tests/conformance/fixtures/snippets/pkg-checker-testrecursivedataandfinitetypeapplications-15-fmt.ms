# conform: tags=closures,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:32 TestRecursiveDataAndFiniteTypeApplications
type Node[T]:
    build: Callable[[], Node[T]]
