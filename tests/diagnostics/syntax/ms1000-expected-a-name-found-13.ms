// conform: tags=diagnostics
// conform: phase=check
interface Named {
    fn name() String
}
fn text(value Named) String {
    return value.|
}
// expect-error: MS1000 7:18-7:19 expected a name, found '|'
