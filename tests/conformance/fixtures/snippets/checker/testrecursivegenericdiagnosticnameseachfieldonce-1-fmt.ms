# conform: tags=alternatives,formatter,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:63 TestRecursiveGenericDiagnosticNamesEachFieldOnce
type Tree[T]:
    case Leaf(value: T)
    case Pair(left: Tree[Int], right: Tree[String])
