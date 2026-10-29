# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 3
import stdout from "@std/io.ms"

type Cell:
    a: Int8
    b: Int32
    c: Float32
    d: Bool
    e: Int16

type Tok:
    case Num(v: Int16, s: Float32)
    case Word(t: String, k: Int8)
    case End

fn kind(t: Tok) Int:
    match t:
        Num(v, s): return v.to_int64() + s.truncate_to_int().get(0)
        Word(text, k): return text.length() + k.to_int64()
        End: return 0

export fn main() Int:
    var l: List[Int32] = []
    for i in 0..1000:
        l.append((1000 - i).to_int32().get(0))

    let sorted = l.sorted(fn a, b: a.compare(b))
    let _ = stdout().write("{sorted[0]} {sorted[999]} {l.length()}\n")
    var m = Map[Int16, Int8]()
    for i in 0..300:
        m.add(i.to_int16().get(0), (i % 100).to_int8().get(0))

    var tot = 0
    for e in m.entries():
        tot += e.value.to_int64()

    let _ = stdout().write("{m.length()} {tot} {m.get(299)}\n")
    var st = Set[Int8]()
    for i in 0..50:
        st.add((i % 7).to_int8().get(0))

    let _ = stdout().write("{st.length()} {st.contains(3)} {st.contains(9)}\n")
    let k: Int8 = -4
    let f: Float32 = 1.25
    let cl: fn(Int) Int = fn x: (x.to_int8().get(0) + k).to_int64()
    let _ = stdout().write("{cl(10)} {f * 2.0 + 0.5}\n")
    var cells: List[Cell] = []
    for i in 0..5:
        cells.append(Cell(a: -1, b: 100000, c: 0.5, d: true, e: -7))

    let _ = stdout().write(
        "{cells[4].b} {cells[2].e} {cells[1].c} {cells[0] == cells[3]} {cells[0].d}\n"
    )
    let _ = stdout().write(
        "{kind(Num(v: 5, s: 2.5))} {kind(Word(t: "ab", k: 3))} {kind(End)}\n"
    )
    let opts: List[Optional[Int8]] = [some(3), none, some(-1)]
    let _ = stdout().write("{opts} {opts[0] == opts[2]}\n")
    let ints: List[Int8] = [5, 3, -9, 1]
    let _ = stdout().write(
        "{ints.sorted(fn a, b: a.compare(b))} {ints.map(fn x: x + 1)} {ints.fold(0, fn a, x: a + x.to_int64())}\n"
    )
    return 0
