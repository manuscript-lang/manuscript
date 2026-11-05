// conform: phase=check
// conform: tags=alternatives,diagnostics,match,tier-core
enum Outcome:
    Success(value: Int)
    Failure

fn value(outcome: Outcome) Int:
    return match outcome:
        Success(number): number
