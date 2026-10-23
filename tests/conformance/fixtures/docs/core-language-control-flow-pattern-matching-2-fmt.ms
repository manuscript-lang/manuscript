# conform: tags=alternatives,formatter,match,modules,parser,records,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:36
import {TextError} from "@std/core.ms"

type Cents:
    case Valid(amount: Int)
    case Invalid

fn total(cents: Cents) Result[Int, TextError]:
    let amount = match cents:
        Valid(value):
            value
        Invalid:
            return error(TextError("Invalid amount"))

    return ok(amount)
