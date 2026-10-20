# conform: tags=alternatives,formatter,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/layout_diagnostics_test.go:18 TestRecursiveDataAndFiniteTypeApplications
type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)
    case Neg(inner: Optional[Expr])
