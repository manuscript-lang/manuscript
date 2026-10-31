import TextError from "@std/core.ms"
import stdout, stdin, read_line, ReadStream from "@std/io.ms"
import clock, Instant from "@std/time.ms"
import StringBuilder from "@std/string.ms"

interface Counter:
    fn bump(by: Int) Int

type Acc:
    total: Int

impl Counter for Acc:
    var fn bump(by: Int) Int:
        self.total += by
        return self.total

type Shape:
    case Circle(r: Int)
    case Square(s: Int)
    case Tri(b: Int)

fn got_line(input: ReadStream) Bool:
    if let line = read_line(input):
        return line.is_some()

    return false

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn since(started: Instant) Int:
    return clock().now().difference(started).to_nanoseconds()

fn report(name: String, ops: Int, started: Instant) Unit:
    say("{name} {ops} {since(started)}\n")

fn ident[T](x: T) T:
    return x

fn checked(n: Int) Int!TextError:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

fn chain(n: Int) Int!TextError:
    let v = try checked(n)
    return ok(v)

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

fn bench_string() Int:
    let t = clock().now()
    var sb = StringBuilder()
    var i = 0

    while i < 50000:
        sb.append("x")
        i += 1

    let built = sb.build()
    report("string_append_50k", 50000, t)
    return built.byte_length()

fn bench_read_line() Unit:
    let t = clock().now()
    let input = stdin()
    var lines = 0
    var more = true

    while more:
        if got_line(input):
            lines += 1
        else:
            more = false

    report("read_line", lines, t)

fn bench_map() Int:
    let t = clock().now()
    var m = Map[Int, Int]()
    var i = 0

    while i < 8000:
        m.add(i, i * 2)
        i += 1

    var sum = 0
    i = 0

    while i < 8000:
        sum += m.get(i).get()
        i += 1

    report("map_put_get_8k", 16000, t)
    return sum

fn bench_int_eq() Int:
    let t = clock().now()
    var hits = 0
    var i = 0

    while i < 10000000:
        if i % 3 == 0:
            hits += 1
        i += 1

    report("int_eq", 10000000, t)
    return hits

fn bench_generic() Int:
    let t = clock().now()
    var i = 0
    var g = 0

    while i < 1000000:
        g += ident[Int](i)
        i += 1

    report("generic_call", 1000000, t)
    return g

fn bench_method() Int:
    let t = clock().now()
    var acc = Acc(0)
    var i = 0

    while i < 1000000:
        acc.bump(1)
        i += 1

    report("method_call", 1000000, t)
    return acc.total

fn bench_try() Int:
    let t = clock().now()
    var i = 0
    var tr = 0

    while i < 1000000:
        if let v = chain(i):
            tr += v
        else:
            tr -= 1

        i += 1

    report("try", 1000000, t)
    return tr

fn bench_match() Int:
    let t = clock().now()
    let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    var i = 0
    var ma = 0

    while i < 1000000:
        ma += area(shapes.get(i % 3))
        i += 1

    report("match", 1000000, t)
    return ma

fn bench_length() Int:
    var xs: List[Int] = []
    var i = 0

    while i < 100:
        xs.append(i)
        i += 1

    let t = clock().now()
    i = 0

    var ln = 0

    while i < 1000000:
        ln += xs.length()
        i += 1

    report("builtin_length", 1000000, t)
    return ln

fn bench_for_list() Int:
    var big: List[Int] = []
    var i = 0

    while i < 1000000:
        big.append(i)
        i += 1

    let t = clock().now()
    var fs = 0
    for x in big:
        fs += x
    report("for_list", 1000000, t)
    return fs

export fn main() Int:
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
    say("# sink {built} {sum} {hits} {g} {total} {tr} {ma} {ln} {fs}\n")
    return 0
