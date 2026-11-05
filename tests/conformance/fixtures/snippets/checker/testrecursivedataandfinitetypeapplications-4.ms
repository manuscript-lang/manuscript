// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:21 TestRecursiveDataAndFiniteTypeApplications
enum Tree[T]:
    Leaf(value: T)
    Branch(left: Tree[T], right: Tree[T])
