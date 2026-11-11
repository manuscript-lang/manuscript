// conform: tags=diagnostics,sets,tier-core
// conform: phase=check
import Closeable from "@std/core.ms"

type Door:
    name: String

fn var Door.close() Unit!: return ok(unit)

fn main() Unit:
    s := Set[Door]()
