// conform: tags=diagnostics
// conform: phase=check
type Item {
    value Int
}
fn text(value Item) String {
    return value.|
}
// expect-error: MS1000 7:18-7:19 expected a name, found '|'
