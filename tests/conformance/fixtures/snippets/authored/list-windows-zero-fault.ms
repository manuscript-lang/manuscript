// conform: tags=lists,faults,tier-core
// conform: phase=run
// conform: origin=List.windows rejects a non-positive size
import stdout from "@std/io/io.ms"

fn main() Unit:
    let _ = stdout().write("{[1, 2, 3].windows(0).length()}\n")
