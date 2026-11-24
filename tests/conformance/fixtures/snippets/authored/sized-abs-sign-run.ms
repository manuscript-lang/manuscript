// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

fn main() Void:
    a Int8 := -100
    b Int32 := -70000
    c Int := -5
    z Int16 := 0
    f Float32 := -2.5
    g Float := -0.0
    void stdout().write(
        f"{a.abs()} {b.abs()} {c.abs()} {a.sign()} {z.sign()} {b.sign()} {c.sign()}\n"
    )
    void stdout().write(f"{f.abs()} {f.sign()} {g.abs()} {g.sign()} {(0.5).sign()}\n")
