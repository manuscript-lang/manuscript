# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 4
import stdout from "@std/io.ms"

export fn main() Int:
    let a: Int8 = -100
    let b: Int32 = -70000
    let c: Int = -5
    let z: Int16 = 0
    let f: Float32 = -2.5
    let g: Float = -0.0
    let _ = stdout().write(
        "{a.abs()} {b.abs()} {c.abs()} {a.sign()} {z.sign()} {b.sign()} {c.sign()}\n"
    )
    let _ = stdout().write("{f.abs()} {f.sign()} {g.abs()} {g.sign()} {(0.5).sign()}\n")
    return 0
