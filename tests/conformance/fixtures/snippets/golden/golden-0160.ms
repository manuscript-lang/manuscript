// conform: tags=diagnostics
// conform: phase=check
fn diagnostic(cause %s) String {
    return cause.message()
}
fn view(cause: %s) Error {
    return cause
}
// expect-error: MS1000 3:21-3:22 expected the type of 'cause' after its name, e.g. cause Int
// expect-error: MS1000 6:14-6:15 remove the ':' between 'cause' and its type; write cause Type
// expect-fix: 6:14-6:15 ""
