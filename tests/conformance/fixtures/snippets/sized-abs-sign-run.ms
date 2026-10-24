# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 4
from "@std/io.ms" import stdout

export def main() -> Int:
    let a: Int8 = -100
    let b: Int32 = -70000
    let c: Int = -5
    let z: Int16 = 0
    let f: Float32 = -2.5
    let g: Float = -0.0
    stdout().write(f"{a.abs()} {b.abs()} {c.abs()} {a.sign()} {z.sign()} {b.sign()} {c.sign()}\n")
    stdout().write(f"{f.abs()} {f.sign()} {g.abs()} {g.sign()} {(0.5).sign()}\n")
    return 0
