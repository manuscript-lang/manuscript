# conform: tags=formatter,generics,interfaces,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:39 TestRecursiveDataAndFiniteTypeApplications
interface Grow[T]:
    fn next() Grow[List[T]]
