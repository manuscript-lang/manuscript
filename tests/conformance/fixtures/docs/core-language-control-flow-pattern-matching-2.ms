# conform: tags=alternatives,diagnostics,match,modules,records,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:36
from "@std/core.ms" import TextError

type Cents:
    case Valid(amount: Int)
    case Invalid

def total(cents: Cents) -> Result[Int, TextError]:
    let amount = match cents:
        case Valid(value):
            value
        case Invalid:
            return error(TextError("Invalid amount"))

    return ok(amount)
