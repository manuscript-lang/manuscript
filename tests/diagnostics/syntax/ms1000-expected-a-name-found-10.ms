// conform: tags=diagnostics
// conform: phase=check
interface Reader {
    fn read() String
}
fn answer[T Reader](reader T) String {
    return reader.|
}
// expect-error: MS1000 7:19-7:20 expected a name, found '|'
