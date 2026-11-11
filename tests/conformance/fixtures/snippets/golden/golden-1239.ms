// conform: tags=diagnostics
// conform: phase=check
type Options:
    required: Int
    count: Int = 3
fn read() Options:
    return Options(required: 1, |)
