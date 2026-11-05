// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:34 TestRecursiveTypesPreserveInitializationAndHashing
enum Expr:
    Num(value: Int)
    Add(left: Expr, right: Expr)

fn value(expr: Expr) Int:
    match expr:
        Num(value): return value
