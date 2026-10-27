# conform: tags=lists,faults,tier-core
# conform: phase=run
# conform: origin=List.chunks rejects a non-positive size
from "@std/io.ms" import stdout

export def main() -> Int:
    let _ = stdout().write(f"{[1, 2, 3].chunks(0).length()}\n")
    return 0
