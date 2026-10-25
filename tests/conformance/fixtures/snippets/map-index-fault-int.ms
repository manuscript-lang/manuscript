# conform: tags=maps,faults,tier-core
# conform: phase=run
# conform: origin=Map and Bytes indexing
from "@std/io.ms" import stdout

export def main() -> Int:
    let counts = {1: 10}
    var bump = counts.clone()
    bump[1] += 5
    stdout().write(f"{bump[1]}\n")
    stdout().write(f"{counts[2]}\n")
    return 0
