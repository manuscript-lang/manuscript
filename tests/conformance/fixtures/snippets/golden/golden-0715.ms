// conform: tags=diagnostics
// conform: phase=check
enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)
fn value(expr: Expr) Int:
    match expr:
        Num(value): return value
