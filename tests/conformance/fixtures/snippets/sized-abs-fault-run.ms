# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 4
from "@std/io.ms" import stdout

export def main() -> Int:
    let m: Int8 = -128
    let _ = stdout().write(f"{m.abs()}\n")
    return 0
