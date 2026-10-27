# conform: tags=numbers,types,faults,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 1
from "@std/io.ms" import stdout

export def main() -> Int:
    let a: Int8 = 100
    let _ = stdout().write("before\n")
    let b = a + a
    let _ = stdout().write(f"{b}\n")
    return 0
