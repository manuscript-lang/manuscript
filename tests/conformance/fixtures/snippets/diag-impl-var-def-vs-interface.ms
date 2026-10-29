# conform: tags=diagnostics,interfaces,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
interface Sink:
    fn put(x: Int) Unit

type Buf:
    n: Int

impl Sink for Buf:
    var fn put(x: Int) Unit:
        self.n = x

export fn main() Int:
    return 0
