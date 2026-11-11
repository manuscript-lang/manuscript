// conform: tags=diagnostics
// conform: phase=check
type Impostor:
    detail: String
fn wrong(value: Impostor) Error:
    return value
