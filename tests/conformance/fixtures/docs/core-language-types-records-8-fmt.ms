# conform: tags=alternatives,control-flow,faults,formatter,match,modules,parser,records,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:99
from "@std/core.ms" import panic

type Expr:
    case Num(value: Int)
    case Add(left: Expr, right: Expr)

def evaluate(expr: Expr) -> Int:
    match expr:
        case Num(value): return value
        case Add(left, right): return evaluate(left) + evaluate(right)

test "recursive expression":
    let expr = Expr.Add(Expr.Num(1), Expr.Num(2))
    if evaluate(expr) != 3:
        panic("unexpected expression value")
