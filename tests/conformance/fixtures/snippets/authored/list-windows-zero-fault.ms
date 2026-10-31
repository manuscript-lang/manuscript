# conform: tags=lists,faults,tier-core
# conform: phase=run
# conform: origin=List.windows rejects a non-positive size
import stdout from "@std/io.ms"

export fn main() Int:
    let _ = stdout().write("{[1, 2, 3].windows(0).length()}\n")
    return 0
