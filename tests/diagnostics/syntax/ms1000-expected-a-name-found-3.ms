// conform: tags=diagnostics
// conform: phase=check
fn count(items List[Int]) Int {
    return items.|
}
// expect-error: MS1000 4:18-4:19 expected a name, found '|'
