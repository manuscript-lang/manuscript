// conform: tags=diagnostics
// conform: phase=check
type Outcome:
    value: Int
fn caller() Unit:
    Outcome(1)
