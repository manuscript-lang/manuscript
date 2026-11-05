// conform: tags=alternatives,diagnostics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/layout_diagnostics_test.go:18 TestRecursiveDataAndFiniteTypeApplications
enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)
    Neg(inner: Expr?)
