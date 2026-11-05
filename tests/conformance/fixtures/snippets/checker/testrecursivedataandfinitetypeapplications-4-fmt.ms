// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:21 TestRecursiveDataAndFiniteTypeApplications
enum Tree[T]:
    Leaf(value: T)
    Branch(left: Tree[T], right: Tree[T])
