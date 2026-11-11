// conform: tags=diagnostics
// conform: phase=check
enum Failure:
    NotFound
    Denied
enum Envelope:
    Pair(left: Failure, right: Failure)
fn use(value: Envelope) Int:
    match value:
        Pair(payload, NotFound): return 1
