// conform: tags=diagnostics
// conform: phase=check
type Options:
    count: Int = 1
    required: Int
fn f() Options: return Options()
