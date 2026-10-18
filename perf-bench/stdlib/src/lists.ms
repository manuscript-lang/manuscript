import range from "@std/collections.ms"
import {bench, ints, Point} from "./harness.ms"

export fn bench_list() Unit:
    let data = ints(100000)
    bench(
        "list.append",
        200000,
        fn() Int:
            let xs: List[Int] = []
            for i in range(0, 200000):
                xs.append(i)
            return xs.length()
    )
    bench(
        "list.at",
        200000,
        fn() Int:
            var n = 0
            for i in range(0, 200000):
                n += data.at(i % 100000).unwrap_or(0)
            return n
    )
    bench(
        "list.for_in",
        100000,
        fn() Int:
            var n = 0
            for x in data:
                n += x
            return n
    )
    bench(
        "list.map",
        100000,
        fn() Int:
            return data.map(fn(x: Int) Int: x * 2).length()
    )
    bench(
        "list.filter",
        100000,
        fn() Int:
            return data.filter(fn(x: Int) Bool: x % 2 == 0).length()
    )
    bench(
        "list.fold",
        100000,
        fn() Int:
            return data.fold(0, fn(acc: Int, x: Int) Int: acc + x)
    )
    bench(
        "list.sorted",
        100000,
        fn() Int:
            return (data.sorted(fn(left: Int, right: Int) Int: left - right).length())
    )
    bench(
        "list.contains",
        100,
        fn() Int:
            var n = 0
            for i in range(0, 100):
                if data.contains(-1): n += 1
            return n
    )
    bench(
        "list.distinct",
        100000,
        fn() Int:
            return data.distinct().length()
    )
    bench(
        "list.concat_reverse",
        100000,
        fn() Int:
            return data.concat(data).reversed().length()
    )
    bench(
        "list.records_map",
        100000,
        fn() Int:
            let points = data.map(fn(x: Int) Point: Point(x, y: x + 1))
            return points.fold(0, fn(acc: Int, p: Point) Int: acc + p.y)
    )
