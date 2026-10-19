# conform: tags=diagnostics,generics,interfaces,lists,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:39 TestRecursiveDataAndFiniteTypeApplications
interface Grow[T]:
    fn next() Grow[List[T]]
