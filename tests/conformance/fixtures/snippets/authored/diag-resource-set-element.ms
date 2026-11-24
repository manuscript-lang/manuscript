// conform: tags=diagnostics,sets,tier-core
// conform: phase=check
import Closeable from "@std/core.ms"

type Door:
    name String

fn move Door.close() Void!: return ok()

fn main() Void:
    s := Set[Door]()
