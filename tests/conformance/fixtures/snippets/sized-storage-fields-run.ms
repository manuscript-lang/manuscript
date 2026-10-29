# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 3
import stdout from "@std/io.ms"

type Pix:
    r: Int8
    g: Int8
    b: Int8
    w: Int16
    f: Float32
    n: Int32

type Shape:
    case Dot(x: Int8)
    case Box(w: Int16, h: Float32, c: Int32)
    case Big(v: Int)

fn area(s: Shape) Int:
    match s:
        Dot(x): return x.to_int64()
        Box(w, h, c): return (w.to_int64() + c.to_int64() + h.truncate_to_int().get(0))
        Big(v): return v

export fn main() Int:
    var l: List[Int8] = []
    for i in 0..10:
        l.append((i * 3 - 12).to_int8().get(0))

    let _ = stdout().write("{l} {l.length()} {l.contains(-3)}\n")
    let s: List[Float32] = [1.5, 0.1, -2.0]
    let _ = stdout().write("{s} {s.contains(0.1)}\n")
    let p = Pix(r: -5, g: 7, b: 127, w: -300, f: 2.5, n: -70000)
    let q = Pix(r: -5, g: 7, b: 127, w: -300, f: 2.5, n: -70000)
    let _ = stdout().write("{p.r} {p.g} {p.b} {p.w} {p.f} {p.n} {p == q}\n")
    let o: Optional[Int16] = some(-2)
    let n: Optional[Int16] = none
    let _ = stdout().write("{o == n} {o == o}\n")
    var m = Map[Int8, Int16]()
    m.add(1, 100)
    m.add(-2, 200)

    let _ = stdout().write("{m.get(-2)} {m.get(1)} {m.length()}\n")
    let _ = stdout().write(
        "{area(Dot(x: -9))} {area(Box(w: -3, h: 4.5, c: 100000))} {area(Big(v: 7))}\n"
    )
    let ps = [p, q]
    let _ = stdout().write("{ps.length()} {ps[1].w}\n")
    return 0
