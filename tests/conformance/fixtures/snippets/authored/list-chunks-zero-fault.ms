# conform: tags=lists,faults,tier-core
# conform: phase=run
# conform: origin=List.chunks rejects a non-positive size
import stdout from "@std/io/io.ms"

export fn main() Int:
    let _ = stdout().write("{[1, 2, 3].chunks(0).length()}\n")
    return 0
