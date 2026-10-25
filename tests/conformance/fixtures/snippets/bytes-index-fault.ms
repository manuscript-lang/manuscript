# conform: tags=faults,tier-core
# conform: phase=run
# conform: origin=Map and Bytes indexing
from "@std/io.ms" import stdout

export def main() -> Int:
    let data = "abc".to_bytes()
    stdout().write(f"{data[-1]}\n")
    stdout().write(f"{data[3]}\n")
    return 0
