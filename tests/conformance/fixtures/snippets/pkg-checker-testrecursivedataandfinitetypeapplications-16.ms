# conform: tags=diagnostics,generics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:33 TestRecursiveDataAndFiniteTypeApplications
interface Node[T]:
    def build() -> Node[T]
