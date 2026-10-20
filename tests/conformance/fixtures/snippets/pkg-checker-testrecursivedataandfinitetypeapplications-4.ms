# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:21 TestRecursiveDataAndFiniteTypeApplications
type Tree[T]:
    case Leaf(value: T)
    case Branch(left: Tree[T], right: Tree[T])
