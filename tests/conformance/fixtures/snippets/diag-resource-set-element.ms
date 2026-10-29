# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit: return

export fn main() Int:
    let s = Set[Door]()
    return 0
