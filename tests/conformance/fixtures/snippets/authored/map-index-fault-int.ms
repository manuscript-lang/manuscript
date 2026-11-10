// conform: tags=maps,faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Unit:
    let counts = {1: 10}
    var bump = counts.clone()
    bump[1] += 5

    let _ = stdout().write("{bump[1]}\n")
    let _ = stdout().write("{counts[2]}\n")
