// conform: tags=diagnostics
// conform: phase=check
enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)
fn tree() Expr: return Expr.Add(left: Expr.Num(1), right: Expr.Num(2))
