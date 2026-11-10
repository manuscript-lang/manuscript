// conform: tags=faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Unit:
    let data = "abc".to_bytes()
    let _ = stdout().write("{data[-1]}\n")
    let _ = stdout().write("{data[3]}\n")
