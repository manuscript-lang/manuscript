# conform: tags=alternatives,diagnostics,match,modules,records,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/pattern-matching.md:36

type Cents:
    case Valid(amount: Int)
    case Invalid

fn total(cents: Cents) Result[Int, Error]:
    let amount = match cents:
        Valid(value):
            value
        Invalid:
            return error(Error("Invalid amount"))

    return ok(amount)
