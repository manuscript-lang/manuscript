from "@std/collections.ms" import range
from "./harness.ms" import bench, ints, Point

export def bench_list() -> Unit:
    let data = ints(100000)

    bench(
        "list.append",
        200000,
        lambda () -> Int:
            var xs: List[Int] = []
            for i in range(0, 200000):
                xs.append(i)
            return xs.length()
    )

    bench(
        "list.at",
        200000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 200000):
                n += data.get(i % 100000, default: 0)
            return n
    )

    bench(
        "list.for_in",
        100000,
        lambda () -> Int:
            var n = 0
            for x in data:
                n += x
            return n
    )

    bench(
        "list.map",
        100000,
        lambda () -> Int:
            return data.map(lambda (x: Int) -> Int: x * 2).length()
    )
    bench(
        "list.filter",
        100000,
        lambda () -> Int:
            return data.filter(lambda (x: Int) -> Bool: x % 2 == 0).length()
    )
    bench(
        "list.fold",
        100000,
        lambda () -> Int:
            return data.fold(0, lambda (acc: Int, x: Int) -> Int: acc + x)
    )
    bench(
        "list.sorted",
        100000,
        lambda () -> Int:
            return (
                data
                .sorted(
                    lambda (left: Int, right: Int) -> Int: left - right
                )
                .length()
            )
    )
    bench(
        "list.sorted_natural", 100000, lambda () -> Int: return data.sorted().length()
    )
    bench("list.sum", 100000, lambda () -> Int: return data.sum())
    bench("list.max", 100000, lambda () -> Int: return data.max().get())

    bench(
        "list.contains",
        100,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100):
                if data.contains(-1): n += 1
            return n
    )

    bench("list.distinct", 100000, lambda () -> Int: return data.distinct().length())
    bench(
        "list.concat_reverse", 100000,
        lambda () -> Int: return data.concat(data).reversed().length()
    )

    bench(
        "list.any_early_exit",
        100000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100000):
                if data.any(lambda (x: Int) -> Bool: x == 0): n += 1
            return n
    )

    let points = data.map(lambda (x: Int) -> Point: Point(x, (x * 7) % 1000))

    bench(
        "list.max_by",
        100,
        lambda () -> Int:
            var n = 0
            for i in range(0, 100):
                if let best = points.max_by(lambda (p: Point) -> Int: p.y): n += best.x
            return n
    )

    bench(
        "list.max_by_loop",
        100,
        lambda () -> Int:
            var n = 0

            for i in range(0, 100):
                var best = points.get(0)
                for p in points:
                    if p.y > best.y: best = p
                n += best.x

            return n
    )

    bench(
        "list.records_map",
        100000,
        lambda () -> Int:
            let points = data.map(lambda (x: Int) -> Point: Point(x, x + 1))
            return points.fold(0, lambda (acc: Int, p: Point) -> Int: acc + p.y)
    )
