// conform: tags=numbers,lexer,formatter,tier-core
// conform: phase=parse
// conform: origin=literals format as written
import stdout from "@std/io/io.ms"

fn main() Unit:
    a := 0xFF_FF
    b := 0b1010_0101
    c := 1_000_000
    d := -0x10
    e: Int32 = 0x7FFF_FFFF
    m := {0xFF: "x"}
    f := 3.141_592
    _ := stdout().write(
        "{a} {b} {c} {d} {e} {f} {0xFF} {m[255]} {-0x8000_0000_0000_0000}\n"
    )
