// conform: tags=alternatives,diagnostics,formatter,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/layout_diagnostics_test.go:63 TestRecursiveGenericDiagnosticNamesEachFieldOnce
enum Tree[T] {
	Leaf(value T)
	Pair(left Tree[Int], right Tree[String])
}
// expect-error: MS3040 6:10 recursive generic applications must preserve their parameters in Tree.Pair.left; keep the same type arguments in the same positions along a recursive cycle
// expect-error: MS3040 6:26 recursive generic applications must preserve their parameters in Tree.Pair.right; keep the same type arguments in the same positions along a recursive cycle
