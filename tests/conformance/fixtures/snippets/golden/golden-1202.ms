// conform: tags=diagnostics
// conform: phase=check
fn work(value Int?) Int {
    return value.|
}
// expect-error: MS1000 4:18-4:19 expected a name, found '|'
