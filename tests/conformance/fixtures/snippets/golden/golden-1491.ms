// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn read() Int
type Reader:
    operation: fn() Int
impl Read for Reader:
    fn read() Int:
        return self.operation()
export fn main() Int:
    view := Read(Reader(fn() Int: 1))
    return view.read()
