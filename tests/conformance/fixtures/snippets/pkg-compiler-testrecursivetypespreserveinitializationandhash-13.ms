# conform: tags=alternatives,diagnostics,match,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:34 TestRecursiveTypesPreserveInitializationAndHashing
type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)
fn value(expr: Expr) Int:
    match expr:
        Num(value): return value
