// A returned `Bytes` is owned, but `view` only borrows its receiver, so returning one (of a local
// or of a parameter) is rejected; copy it with `.clone()` after the view.
import Bytes from "@std/bytes.ms"

fn result() Bytes:
    let bytes = Bytes([10, 20, 30])
    return bytes.view(1, 3)

export fn main() Int:
    return result().length()
