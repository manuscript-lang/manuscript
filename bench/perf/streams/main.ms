import (
    stdout, Source from "@std/io/io.ms",
    from_list,
    from_bytes,
    map,
    lines,
    collect,
    filter,
    take,
    fold from "@std/io/streams.ms",
    Bytes, BytesBuilder from "@std/bytes.ms",
    monotonic, Instant from "@std/time.ms",
)

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
        if self.at >= self.items.length(): return ok(none)

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
        if let v = step: return ok(self.f(v))

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
    for item in from_list(xs) | map(fn x: x + 1):
        total += item
    return ok(total)

fn stdlib_map3(xs: List[Int]) Int!:
    var total = 0
    for item in from_list(xs) | map(fn x: x + 1) | map(fn x: x * 3) | map(fn x: x - 2):
        total += item
    return ok(total)

fn stdlib_collect(xs: List[Int]) Int!:
    let all = try collect(from_list(xs) | map(fn x: x + 1), none)
    return ok(all.length())

fn plain_filter(xs: List[Int]) Int:
    var total = 0
    for x in xs:
        if x % 2 == 0:
            total += x
    return total

fn stdlib_filter(xs: List[Int]) Int!:
    var total = 0
    for item in from_list(xs) | filter(fn x: x % 2 == 0):
        total += item
    return ok(total)

fn plain_take(xs: List[Int], count: Int) Int:
    var total = 0
    var seen = 0

    for x in xs:
        if seen >= count: break

        total += x
        seen += 1

    return total

fn stdlib_take(xs: List[Int], count: Int) Int!:
    var total = 0
    for item in from_list(xs) | take(count):
        total += item
    return ok(total)

fn stdlib_fold(xs: List[Int]) Int!:
    return fold(from_list(xs), 0, fn total, x: total + x)

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
    for line in from_bytes(data) | lines:
        count += line.length()
    return ok(count)

fn main() Unit:
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
    t = monotonic()
    report("for-filter", n, t, plain_filter(xs))

    let g = xs.clone()
    t = monotonic()
    report("stream-filter", n, t, stdlib_filter(g).get(-1))
    t = monotonic()
    report("for-take", n, t, plain_take(xs, n / 2))

    let h = xs.clone()
    t = monotonic()
    report("stream-take", n / 2, t, stdlib_take(h, n / 2).get(-1))

    let k = xs.clone()
    t = monotonic()
    report("stream-fold", n, t, stdlib_fold(k).get(-1))

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
