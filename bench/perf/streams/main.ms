import stdout, Source from "@std/io/io.ms"
import from_list, from_bytes, map, lines, collect from "@std/io/streams.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import monotonic, Instant from "@std/os/time.ms"

// ns per item for stream pipelines against the loops they replace. One line per case: `name ns checksum`.

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn report(name: String, n: Int, start: Instant, sum: Int) Unit:
    let ns = monotonic().difference(start).to_nanoseconds()
    say("{name} {ns.to_float() / n.to_float()} {sum}\n")

// A list as a `Source`, read by index.
type ListSource:
    items: List[Int]
    at: Int

impl Source[Int] for ListSource:
    var fn next() Int?!:
        if self.at >= self.items.length():
            return ok(none)

        let v = self.items[self.at]
        self.at += 1
        return ok(v)

    var fn close() Unit!:
        return ok(unit)

// `f` over another `Source`, called through the interface.
type MapSource:
    up: Source[Int]
    f: fn(Int) Int

impl Source[Int] for MapSource:
    var fn next() Int?!:
        let step = try self.up.next()
        if let v = step:
            return ok(self.f(v))

        return ok(none)

    var fn close() Unit!:
        return self.up.close()

fn plain(xs: List[Int]) Int:
    var total = 0
    for x in xs:
        total += x + 1
    return total

fn drain(source: Source[Int]) Int!:
    var s = source
    var total = 0

    while true:
        let step = try s.next()

        if let v = step:
            total += v
        else:
            break

    return ok(total)

fn stdlib_map(xs: List[Int]) Int!:
    var total = 0
    for item in (from_list(xs) | map(fn x: x + 1)).wait():
        total += try item
    return ok(total)

fn stdlib_map3(xs: List[Int]) Int!:
    var total = 0
    for item in (from_list(xs) | map(fn x: x + 1) | map(fn x: x * 3) | map(fn x: x - 2)).wait():
        total += try item
    return ok(total)

fn stdlib_collect(xs: List[Int]) Int!:
    let all = try collect(from_list(xs) | map(fn x: x + 1), none)
    return ok(all.length())

fn hand_lines(data: Bytes) Int!:
    var count = 0
    var at = 0

    while true:
        let end = data.index_of_byte(10, at)

        if let stop = end:
            let line = try data.slice(at, stop)
            if let text = line.decode_utf8():
                count += text.length()
            at = stop + 1
        else:
            break

    return ok(count)

fn stdlib_lines(data: Bytes) Int!:
    var count = 0
    for line in (from_bytes(data) | lines).wait():
        count += (try line).length()
    return ok(count)

export fn main() Int:
    let n = 5000000
    var xs = List[Int]()
    for i in 0..n:
        xs.append(i)

    var t = monotonic()
    report("for-list", n, t, plain(xs))

    let a = xs.clone()
    t = monotonic()
    report("source-list", n, t, drain(ListSource(a, 0)).get(-1))

    let b = xs.clone()
    t = monotonic()
    report("source-map", n, t, drain(MapSource(ListSource(b, 0), fn x: x + 1)).get(-1))

    let c = xs.clone()
    t = monotonic()
    report("stream-map", n, t, stdlib_map(c).get(-1))

    let d = xs.clone()
    t = monotonic()
    report("stream-map3", n, t, stdlib_map3(d).get(-1))

    let e = xs.clone()
    t = monotonic()
    report("stream-collect", n, t, stdlib_collect(e).get(-1))

    var builder = BytesBuilder()
    let rows = 1000000
    for i in 0..rows:
        builder.append_bytes("line number {i} of the log\n".to_bytes())

    let data = builder.build()
    t = monotonic()
    report("hand-lines", rows, t, hand_lines(data).get(-1))

    let f = data.clone()
    t = monotonic()
    report("stream-lines", rows, t, stdlib_lines(f).get(-1))
    return 0
