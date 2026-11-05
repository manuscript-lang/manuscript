// conform: phase=check
// conform: tags=alternatives,diagnostics,match,tier-core
enum Outcome:
    case Success(value: Int)
    case Failure

fn value(outcome: Outcome) Int:
    return match outcome:
        Success(number): number
