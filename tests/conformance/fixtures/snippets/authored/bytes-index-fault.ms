// conform: tags=faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Unit:
    data := "abc".to_bytes()
    _ := stdout().write("{data[-1]}\n")
    _ := stdout().write("{data[3]}\n")
