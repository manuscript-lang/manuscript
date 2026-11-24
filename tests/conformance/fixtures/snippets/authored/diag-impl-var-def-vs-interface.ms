// conform: tags=diagnostics,interfaces,mutation,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
interface Sink:
    fn put(x Int) Void

type Buf:
    n Int

fn var Buf.put(x Int) Void:
    self.n = x

fn main() Void:
    return
