# conform: tags=numbers,lexer,tier-core
# conform: phase=run
# conform: origin=hex, binary and separator literals
from "@std/io.ms" import stdout

export def main() -> Int:
    let a = 0xFF_FF
    let b = 0b1010_0101
    let c = 1_000_000
    let d = -0x10
    let e: Int32 = 0x7FFF_FFFF
    let m = {0xFF: "x"}
    let f = 3.141_592
    stdout().write(f"{a} {b} {c} {d} {e} {f} {0xFF} {m[255]} {-0x8000_0000_0000_0000}\n")
    return 0
