from "@std/core.ms" import TextError
from "@std/io.ms" import stdout, stdin, read_line, ReadStream
from "@std/time.ms" import clock, Instant
from "@std/string.ms" import StringBuilder

interface Counter:
    var def bump(by: Int) -> Int

type Acc:
    total: Int

impl Counter for Acc:
    var def bump(by: Int) -> Int:
        self.total += by
        return self.total

type Shape:
    case Circle(r: Int)
    case Square(s: Int)
    case Tri(b: Int)

def got_line(input: ReadStream) -> Bool:
    if let line = read_line(input):
        return line.is_some()

    return False

def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

def since(started: Instant) -> Int:
    return clock().now().difference(started).to_nanoseconds()

def report(name: String, ops: Int, started: Instant) -> Unit:
    say(f"{name} {ops} {since(started)}\n")

def ident[T](x: T) -> T:
    return x

def checked(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

def chain(n: Int) -> Result[Int, TextError]:
    let v = try checked(n)
    return ok(v)

def area(s: Shape) -> Int:
    var out = 0

    match s:
        case Circle(r):
            out = r * 3
        case Square(side):
            out = side * side
        case Tri(b):
            out = b

    return out

def bench_string() -> Int:
    let t = clock().now()
    var sb = StringBuilder()
    var i = 0

    while i < 50000:
        sb.append("x")
        i += 1

    let built = sb.build()
    report("string_append_50k", 50000, t)
    return built.byte_length()

def bench_read_line() -> Unit:
    let t = clock().now()
    let input = stdin()
    var lines = 0
    var more = True

    while more:
        if got_line(input):
            lines += 1
        else:
            more = False

    report("read_line", lines, t)

def bench_map() -> Int:
    let t = clock().now()
    var m = Map[Int, Int]()
    var i = 0

    while i < 8000:
        m.add(i, i * 2)
        i += 1

    var sum = 0
    i = 0

    while i < 8000:
        sum += m[i]
        i += 1

    report("map_put_get_8k", 16000, t)
    return sum

def bench_int_eq() -> Int:
    let t = clock().now()
    var hits = 0
    var i = 0

    while i < 10000000:
        if i % 3 == 0:
            hits += 1
        i += 1

    report("int_eq", 10000000, t)
    return hits

def bench_generic() -> Int:
    let t = clock().now()
    var i = 0
    var g = 0

    while i < 100000000:
        g += ident[Int](i)
        i += 1

    report("generic_call", 100000000, t)
    return g

def bench_method() -> Int:
    let t = clock().now()
    var acc = Acc(0)
    var i = 0

    while i < 100000000:
        acc.bump(1)
        i += 1

    report("method_call", 100000000, t)
    return acc.total

def bench_try() -> Int:
    let t = clock().now()
    var i = 0
    var tr = 0

    while i < 100000000:
        if let v = chain(i):
            tr += v
        else:
            tr -= 1

        i += 1

    report("try", 100000000, t)
    return tr

def bench_match() -> Int:
    let t = clock().now()
    let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    var i = 0
    var ma = 0

    while i < 100000000:
        ma += area(shapes.get(i % 3))
        i += 1

    report("match", 100000000, t)
    return ma

def bench_length() -> Int:
    var xs: List[Int] = []
    var i = 0

    while i < 100:
        xs.append(i)
        i += 1

    let t = clock().now()
    i = 0

    var ln = 0

    while i < 100000000:
        ln += xs.length()
        i += 1

    report("builtin_length", 100000000, t)
    return ln

def bench_for_list() -> Int:
    var big: List[Int] = []
    var i = 0

    while i < 1000000:
        big.append(i)
        i += 1

    let t = clock().now()
    var fs = 0
    var rep = 0

    while rep < 100:
        for x in big:
            fs += x
        rep += 1

    report("for_list", 100000000, t)
    return fs

export def main() -> Int:
    let built = bench_string()
    bench_read_line()

    let sum = bench_map()
    let hits = bench_int_eq()
    let g = bench_generic()
    let total = bench_method()
    let tr = bench_try()
    let ma = bench_match()
    let ln = bench_length()
    let fs = bench_for_list()
    say(f"# sink {built} {sum} {hits} {g} {total} {tr} {ma} {ln} {fs}\n")
    return 0
