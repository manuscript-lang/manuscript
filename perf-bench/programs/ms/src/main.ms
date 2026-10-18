import {stdout, stdin, read_line} from "@std/io.ms"
import {clock, Instant} from "@std/time.ms"
import {StringBuilder} from "@std/string.ms"

interface Counter:
    fn bump(by: Int) Int

type Acc:
    total: Int

impl Counter for Acc:
    fn bump(by: Int) Int:
        self.total = self.total + by
        return self.total

type Shape:
    case Circle(r: Int)
    case Square(s: Int)
    case Tri(b: Int)

fn got_line() Bool:
    match read_line(input: stdin()):
        ok(line):
            return line.is_some()
        error(_):
            return false

fn say(text: String) Unit:
    match stdout().write(data: text.to_bytes()):
        ok(_):
            unit
        error(_):
            unit

fn since(started: Instant) Int:
    return clock().now().difference(other: started).to_nanoseconds()

fn report(name: String, ops: Int, started: Instant) Unit:
    say("{name} {ops} {since(started)}\n")

fn ident[T](x: T) T:
    return x

fn checked(n: Int) Result[Int, String]:
    if n < 0:
        return error(cause: "negative")

    return ok(value: n + 1)

fn chain(n: Int) Result[Int, String]:
    let v = try checked(n)
    return ok(value: v)

fn area(s: Shape) Int:
    var out = 0

    match s:
        Circle(r):
            out = r * 3
        Square(side):
            out = side * side
        Tri(b):
            out = b

    return out

export fn main() Int:
    # string_append: 50k appends
    var t = clock().now()
    let sb = StringBuilder()
    var i = 0

    while i < 50000:
        sb.append("x")
        i = i + 1

    let built = sb.freeze()
    report(name: "string_append_50k", ops: 50000, started: t)
    # read_line: every line on stdin
    t = clock().now()
    var lines = 0
    var more = true

    while more:
        if got_line():
            lines = lines + 1
        else:
            more = false

    report(name: "read_line", ops: lines, started: t)
    # map_put_get: 8k Int keys
    t = clock().now()
    let m = Map[Int, Int]()
    i = 0

    while i < 8000:
        m.add(key: i, value: i * 2)
        i = i + 1

    var sum = 0
    i = 0

    while i < 8000:
        sum = sum + m.get(key: i).unwrap()
        i = i + 1

    report(name: "map_put_get_8k", ops: 16000, started: t)
    # int_eq
    t = clock().now()
    var hits = 0
    i = 0

    while i < 10000000:
        if i % 3 == 0:
            hits = hits + 1
        i = i + 1

    report(name: "int_eq", ops: 10000000, started: t)
    # generic call
    t = clock().now()
    i = 0
    var g = 0

    while i < 1000000:
        g = g + ident[Int](i)
        i = i + 1

    report(name: "generic_call", ops: 1000000, started: t)
    # method call
    t = clock().now()
    let acc = Acc(total: 0)
    i = 0

    while i < 1000000:
        acc.bump(by: 1)
        i = i + 1

    report(name: "method_call", ops: 1000000, started: t)
    # try
    t = clock().now()
    i = 0
    var tr = 0

    while i < 1000000:
        match chain(i):
            ok(v):
                tr = tr + v
            error(_):
                tr = tr - 1

        i = i + 1

    report(name: "try", ops: 1000000, started: t)
    # statement match
    t = clock().now()
    let shapes = [Shape.Circle(r: 2), Shape.Square(s: 3), Shape.Tri(b: 4)]
    i = 0
    var ma = 0

    while i < 1000000:
        ma = ma + area(shapes.at(i % 3).unwrap())
        i = i + 1

    report(name: "match", ops: 1000000, started: t)
    # builtin method: length()
    t = clock().now()
    let xs: List[Int] = []
    i = 0

    while i < 100:
        xs.append(i)
        i = i + 1

    i = 0
    var ln = 0

    while i < 1000000:
        ln = ln + xs.length()
        i = i + 1

    report(name: "builtin_length", ops: 1000000, started: t)
    # for loop over a list
    let big: List[Int] = []
    i = 0

    while i < 1000000:
        big.append(i)
        i = i + 1

    t = clock().now()
    var fs = 0
    for x in big:
        fs = fs + x
    report(name: "for_list", ops: 1000000, started: t)
    say(
        "# sink {built.byte_length()} {sum} {hits} {g} {acc.total} {tr} {ma} {ln} {fs}\n"
    )
    return 0
