import stdout from "@std/io/io.ms"

type Source:
    choices: List[Int]
    pos: Int

type Drawn[T]:
    value: T
    source: Source

type Gen[T]:
    make: fn(Source) Drawn[T]

fn draw(source: Source) Drawn[Int]:
    var s = source
    let value = s.choices[s.pos]
    s.pos += 1
    return Drawn(value, s)

fn ints() Gen[Int]:
    return Gen[Int](fn s: ints_draw(s))

fn ints_draw(s: Source) Drawn[Int]:
    let {value: sign, source: middle} = draw(s)
    let {value, source} = draw(middle)
    return Drawn(value + sign, source)

export fn main() Int:
    let c = ints().make(Source([0, 3, 0, 7], 0))
    let _ = stdout().write("{c.value} {c.source.choices}\n")
    return 0
