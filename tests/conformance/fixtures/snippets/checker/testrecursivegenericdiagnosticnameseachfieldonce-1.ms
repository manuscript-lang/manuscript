// conform: tags=alternatives,diagnostics,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:63 TestRecursiveGenericDiagnosticNamesEachFieldOnce
enum Tree[T]:
    Leaf(value: T)
    Pair(left: Tree[Int], right: Tree[String])
