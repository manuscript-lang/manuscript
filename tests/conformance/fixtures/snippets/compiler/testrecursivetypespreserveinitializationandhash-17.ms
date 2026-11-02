# conform: tags=alternatives,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:50 TestRecursiveTypesPreserveInitializationAndHashing
type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)

fn tree() Expr: return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
