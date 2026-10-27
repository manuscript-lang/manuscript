# conform: tags=numbers,faults,tier-core
# conform: phase=run
# conform: origin=unsigned integer types stage 1
from "@std/io.ms" import stdout

export def main() -> Int:
    let a: UInt8 = 5
    let b: UInt8 = 6
    let _ = stdout().write("before\n")
    let c = a - b
    let _ = stdout().write(f"{c}\n")
    return 0
