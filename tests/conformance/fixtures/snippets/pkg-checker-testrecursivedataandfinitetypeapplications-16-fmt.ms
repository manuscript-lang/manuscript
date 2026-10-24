# conform: tags=formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:33 TestRecursiveDataAndFiniteTypeApplications
interface Node[T]:
    def build() -> Node[T]
