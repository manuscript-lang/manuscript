// conform: tags=diagnostics
// conform: phase=check
type Options:
    first: Int = 3
    second: Int = first + 1
fn read() Int: return Options().first
