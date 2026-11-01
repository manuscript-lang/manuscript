import keep, measure from "@std/test/bench.ms"
import ints, Point from "./src/harness.ms"

# Index of the greatest key; `key` is a known lambda at every call site (see proposals/specialize-closure-args.md).
fn best_index(points: List[Point], key: fn(Point) Int) Int:
    var best = 0
    var best_key = key(points.get(0, default: Point(x: 0, y: 0)))

    for i in 1..points.length():
        let k = key(points.get(i, default: Point(x: 0, y: 0)))

        if k > best_key:
            best_key = k
            best = i

    return best

fn best_index_loop(points: List[Point], scale: Int) Int:
    var best = 0
    var best_key = points.get(0, default: Point(x: 0, y: 0)).y * scale

    for i in 1..points.length():
        let k = points.get(i, default: Point(x: 0, y: 0)).y * scale

        if k > best_key:
            best_key = k
            best = i

    return best

bench "list.callable_key":
    var points: List[Point] = []
    for i in 0..100000:
        points.append(Point(x: i, y: (i * 7919) % 10007))

    let scale = 3
    fn work() Result[Unit, Error]:
        return keep(best_index(points, fn(p: Point) Int: p.y * scale))
    try measure(100000, work)

bench "list.callable_key_loop":
    var points: List[Point] = []
    for i in 0..100000:
        points.append(Point(x: i, y: (i * 7919) % 10007))

    let scale = 3
    try measure(100000, fn: keep(best_index_loop(points, scale)))

bench "list.append":
    fn work() Result[Unit, Error]:
        var xs: List[Int] = []
        for i in 0..200000:
            xs.append(i)
        return keep(xs.length())

    try measure(200000, work)

bench "list.at":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..200000:
            n += data.get(i % 100000, default: 0)
        return keep(n)

    try measure(200000, work)

bench "list.for_in":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for x in data:
            n += x
        return keep(n)

    try measure(100000, work)

bench "list.map":
    let data = ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.map(fn(x: Int) Int: x * 2).length())
    try measure(100000, work)

bench "list.filter":
    let data = ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.filter(fn(x: Int) Bool: x % 2 == 0).length())
    try measure(100000, work)

bench "list.zip":
    let data = ints(100000)
    try measure(100000, fn: keep(data.zip(data).length()))

bench "list.chunks":
    let data = ints(100000)
    try measure(100000, fn: keep(data.chunks(64).length()))

bench "list.windows":
    let data = ints(100000)
    try measure(100000, fn: keep(data.windows(4).length()))

bench "list.partition":
    let data = ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.partition(fn(x: Int) Bool: x % 2 == 0).matching.length())
    try measure(100000, work)

bench "list.fold":
    let data = ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.fold(0, fn(acc: Int, x: Int) Int: acc + x))
    try measure(100000, work)

bench "list.sorted":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        let sorted = data.sorted(fn(left: Int, right: Int) Int: left - right)
        return keep(sorted.length())

    try measure(100000, work)

bench "list.sorted_natural":
    let data = ints(100000)
    try measure(100000, fn: keep(data.sorted().length()))

bench "list.sum":
    let data = ints(100000)
    try measure(100000, fn: keep(data.sum()))

bench "list.max":
    let data = ints(100000)
    try measure(100000, fn: keep(data.max().get()))

bench "list.contains":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100:
            if data.contains(-1): n += 1
        return keep(n)

    try measure(100, work)

bench "list.distinct":
    let data = ints(100000)
    try measure(100000, fn: keep(data.distinct().length()))

bench "list.concat_reverse":
    let data = ints(100000)
    try measure(100000, fn: keep(data.concat(data).reversed().length()))

bench "list.any_early_exit":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            if data.any(fn(x: Int) Bool: x == 0): n += 1
        return keep(n)

    try measure(100000, work)

bench "list.max_by":
    let data = ints(100000)
    let small_points = data.map(fn(x: Int) Point: Point(x, (x * 7) % 1000))

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100:
            if let best = small_points.max_by(fn(p: Point) Int: p.y): n += best.x
        return keep(n)

    try measure(100, work)

bench "list.max_by_loop":
    let data = ints(100000)
    let small_points = data.map(fn(x: Int) Point: Point(x, (x * 7) % 1000))

    fn work() Result[Unit, Error]:
        var n = 0

        for i in 0..100:
            var best = 0
            for j in 1..small_points.length():
                if small_points[j].y > small_points[best].y: best = j
            n += small_points[best].x

        return keep(n)

    try measure(100, work)

bench "list.records_map":
    let data = ints(100000)

    fn work() Result[Unit, Error]:
        let mapped = data.map(fn(x: Int) Point: Point(x, x + 1))
        return keep(mapped.fold(0, fn(acc: Int, p: Point) Int: acc + p.y))

    try measure(100000, work)
