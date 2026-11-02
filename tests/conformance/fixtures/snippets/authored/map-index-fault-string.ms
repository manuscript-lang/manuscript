# conform: tags=maps,faults,tier-core
# conform: phase=run
# conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

export fn main() Int:
    let scores = {"ann": 1, "bob": 2}
    let _ = stdout().write("{scores["ann"]}\n")
    let _ = stdout().write("{scores["eve"]}\n")
    return 0
