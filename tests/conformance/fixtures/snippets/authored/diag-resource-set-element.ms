// conform: tags=diagnostics,sets,tier-core
// conform: phase=check
import Closeable from "@std/core.ms"

type Door:
    name: String

fn var Door.close() Void!: return ok(void)

fn main() Void:
    s := Set[Door]()
