// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:50 TestRecursiveTypesPreserveInitializationAndHashing
enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)

fn tree() Expr: return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
