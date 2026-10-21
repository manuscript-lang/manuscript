# conform: tags=alternatives,control-flow,faults,formatter,match,modules,parser,records,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:99
import panic from "@std/core.ms"

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)

fn evaluate(expr: Expr) Int:
    match expr:
        Num(value): return value
        Add(left, right): return evaluate(left) + evaluate(right)

test "recursive expression":
    let expr = Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
