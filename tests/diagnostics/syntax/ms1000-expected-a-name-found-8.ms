// conform: tags=diagnostics
// conform: phase=check
fn work() Int? {
    return Int?.|
}
// expect-error: MS1000 4:17-4:18 expected a name, found '|'
