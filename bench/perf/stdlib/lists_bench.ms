import keep, measure from "@std/test/bench.ms"
import ints, Point from "./src/harness.ms"

// Index of the greatest key; `key` is a known lambda at every call site (see proposals/specialize-closure-args.md).
fn best_index(points: List[Point], key: fn(Point) Int) Int:
    var best = 0
    var best_key = key(points.get(0, default: Point(x: 0, y: 0)))

    for i in 1..points.length():
        k := key(points.get(i, default: Point(x: 0, y: 0)))

        if k > best_key:
            best_key = k
            best = i

    return best

fn best_index_loop(points: List[Point], scale: Int) Int:
    var best = 0
    var best_key = points.get(0, default: Point(x: 0, y: 0)).y * scale

    for i in 1..points.length():
        k := points.get(i, default: Point(x: 0, y: 0)).y * scale

        if k > best_key:
            best_key = k
            best = i

    return best

bench "list.callable_key":
    var points: List[Point] = []
    for i in 0..100000:
        points.append(Point(x: i, y: (i * 7919) % 10007))

    scale := 3
    fn work() Result[Unit, Error]:
        return keep(best_index(points, fn(p: Point) Int: p.y * scale))
    try measure(100000, work)

bench "list.callable_key_loop":
    var points: List[Point] = []
    for i in 0..100000:
        points.append(Point(x: i, y: (i * 7919) % 10007))

    scale := 3
    try measure(100000, fn: keep(best_index_loop(points, scale)))

bench "list.append":
    fn work() Result[Unit, Error]:
        var xs: List[Int] = []
        for i in 0..200000:
            xs.append(i)
        return keep(xs.length())

    try measure(200000, work)

bench "list.at":
    data := ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..200000:
            n += data.get(i % 100000, default: 0)
        return keep(n)

    try measure(200000, work)

bench "list.for_in":
    data := ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for x in data:
            n += x
        return keep(n)

    try measure(100000, work)

bench "list.map":
    data := ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.map(fn(x: Int) Int: x * 2).length())
    try measure(100000, work)

bench "list.filter":
    data := ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.filter(fn(x: Int) Bool: x % 2 == 0).length())
    try measure(100000, work)

bench "list.zip":
    data := ints(100000)
    try measure(100000, fn: keep(data.zip(data).length()))

bench "list.chunks":
    data := ints(100000)
    try measure(100000, fn: keep(data.chunks(64).length()))

bench "list.windows":
    data := ints(100000)
    try measure(100000, fn: keep(data.windows(4).length()))

bench "list.partition":
    data := ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.partition(fn(x: Int) Bool: x % 2 == 0).matching.length())
    try measure(100000, work)

bench "list.fold":
    data := ints(100000)
    fn work() Result[Unit, Error]:
        return keep(data.fold(0, fn(acc: Int, x: Int) Int: acc + x))
    try measure(100000, work)

bench "list.sorted":
    data := ints(100000)

    fn work() Result[Unit, Error]:
        sorted := data.sorted(fn(left: Int, right: Int) Int: left - right)
        return keep(sorted.length())

    try measure(100000, work)

bench "list.sorted_natural":
    data := ints(100000)
    try measure(100000, fn: keep(data.sorted().length()))

bench "list.sum":
    data := ints(100000)
    try measure(100000, fn: keep(data.sum()))

bench "list.max":
    data := ints(100000)
    try measure(100000, fn: keep(data.max().get()))

bench "list.contains":
    data := ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100:
            if data.contains(-1): n += 1
        return keep(n)

    try measure(100, work)

bench "list.distinct":
    data := ints(100000)
    try measure(100000, fn: keep(data.distinct().length()))

bench "list.concat_reverse":
    data := ints(100000)
    try measure(100000, fn: keep(data.concat(data).reversed().length()))

bench "list.any_early_exit":
    data := ints(100000)

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            if data.any(fn(x: Int) Bool: x == 0): n += 1
        return keep(n)

    try measure(100000, work)

bench "list.max_by":
    data := ints(100000)
    small_points := data.map(fn(x: Int) Point: Point(x, (x * 7) % 1000))

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100:
            if best := small_points.max_by(fn(p: Point) Int: p.y): n += best.x
        return keep(n)

    try measure(100, work)

bench "list.max_by_loop":
    data := ints(100000)
    small_points := data.map(fn(x: Int) Point: Point(x, (x * 7) % 1000))

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
    data := ints(100000)

    fn work() Result[Unit, Error]:
        mapped := data.map(fn(x: Int) Point: Point(x, x + 1))
        return keep(mapped.fold(0, fn(acc: Int, p: Point) Int: acc + p.y))

    try measure(100000, work)

bench "list.repeated empty":
    values: List[Int] = []
    fn work() Unit!:
        return keep(values.repeated(1000000).length())
    try measure(1, work)

bench "list.repeated small":
    values := [1, 2, 3, 4]
    fn work() Unit!:
        return keep(values.repeated(2).length())
    try measure(1, work)
