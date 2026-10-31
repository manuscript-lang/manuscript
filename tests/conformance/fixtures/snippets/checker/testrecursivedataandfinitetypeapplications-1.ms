# conform: tags=alternatives,diagnostics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/layout_diagnostics_test.go:18 TestRecursiveDataAndFiniteTypeApplications
type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)
    case Neg(inner: Expr?)
