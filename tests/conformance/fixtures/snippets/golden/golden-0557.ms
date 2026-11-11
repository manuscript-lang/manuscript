// conform: tags=diagnostics
// conform: phase=check
import Closeable from "@std/cleanup.ms"
impl Closeable for Box[T]:
    fn close() Unit:
        return
export fn loaded() Int:
    return 1
