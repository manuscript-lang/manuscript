// conform: tags=diagnostics,sets,tier-core
// conform: phase=check
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!: return ok(unit)

fn main() Unit:
    let s = Set[Door]()
