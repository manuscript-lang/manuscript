// conform: tags=diagnostics
// conform: phase=check
interface Reader:
    fn read() String
fn answer[T: Reader](reader: T) String:
    return reader.|
