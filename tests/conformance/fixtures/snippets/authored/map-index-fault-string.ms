// conform: tags=maps,faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

export fn main() Int:
    scores := {"ann": 1, "bob": 2}
    _ := stdout().write("{scores["ann"]}\n")
    _ := stdout().write("{scores["eve"]}\n")
    return 0
