from "@std/io.ms" import stdout

type Source:
    choices: List[Int]
    pos: Int

type Drawn[T]:
    value: T
    source: Source

type Gen[T]:
    make: Callable[[Source], Drawn[T]]

def draw(source: Source) -> Drawn[Int]:
    var s = source
    let value = s.choices[s.pos]
    s.pos += 1
    return Drawn(value, s)

def ints() -> Gen[Int]:
    return Gen[Int](lambda s: ints_draw(s))

def ints_draw(s: Source) -> Drawn[Int]:
    let {value: sign, source: middle} = draw(s)
    let {value, source} = draw(middle)
    return Drawn(value + sign, source)

export def main() -> Int:
    let c = ints().make(Source([0, 3, 0, 7], 0))
    let _ = stdout().write(f"{c.value} {c.source.choices}\n")
    return 0
