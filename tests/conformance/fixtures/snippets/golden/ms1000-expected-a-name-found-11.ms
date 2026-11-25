// conform: tags=diagnostics
// conform: phase=check
fn text(value Bool) String {
    return value.|
}
// expect-error: MS1000 4:18-4:19 expected a name, found '|'
