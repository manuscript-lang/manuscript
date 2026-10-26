# conform: tags=diagnostics,interfaces,mutation,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
interface Sink:
    def put(x: Int) -> Unit
type Buf:
    n: Int
impl Sink for Buf:
    var def put(x: Int) -> Unit:
        self.n = x
export def main() -> Int:
    return 0
