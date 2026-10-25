from "@std/collections.ms" import range
from "./harness.ms" import bench, words

type Cell:
    x: Int
    y: Int

export def bench_map_set() -> Unit:
    bench(
        "map.int_put_get",
        200000,
        lambda () -> Int:
            var m = Map[Int, Int]()
            for i in range(0, 100000):
                m.add(i, i * 2)

            var n = 0
            for i in range(0, 100000):
                n += m.get(i).get(0)
            return n
    )

    bench(
        "map.record_key_get",
        200000,
        lambda () -> Int:
            var m = Map[Cell, Int]()
            for i in range(0, 100000):
                m.add(Cell(x: i, y: i * 2), i)

            var n = 0
            for i in range(0, 100000):
                n += m.get(Cell(x: i, y: i * 2)).get(0)
            return n
    )

    bench(
        "map.string_put_get",
        100000,
        lambda () -> Int:
            let keys = words(50000)
            var m = Map[String, Int]()
            for k in keys:
                m.add(k.clone(), 1)

            var n = 0
            for k in keys:
                n += m.get(k).get(0)
            return n
    )

    bench(
        "map.get_let",
        100000,
        lambda () -> Int:
            let keys = words(50000)
            var m = Map[String, String]()
            for k in keys:
                m.add(k.clone(), k.clone())

            var n = 0

            for k in keys:
                let found = m.get(k)
                if found.is_some():
                    n += found.get().length()

            return n
    )

    bench(
        "map.get_if_let",
        100000,
        lambda () -> Int:
            let keys = words(50000)
            var m = Map[String, String]()
            for k in keys:
                m.add(k.clone(), k.clone())

            var n = 0
            for k in keys:
                if let v = m.get(k):
                    n += v.length()
            return n
    )

    bench(
        "map.get_chain",
        100000,
        lambda () -> Int:
            let keys = words(50000)
            var m = Map[String, String]()
            for k in keys:
                m.add(k.clone(), k.clone())

            var n = 0
            for k in keys:
                n += m.get(k).get("").length()
            return n
    )

    bench(
        "map.get_or",
        100000,
        lambda () -> Int:
            let keys = words(50000)
            var m = Map[String, String]()
            for k in keys:
                m.add(k.clone(), k.clone())

            var n = 0
            for k in keys:
                n += m.get_or(key: k, fallback: "").length()
            return n
    )

    bench(
        "map.iterate_entries",
        100000,
        lambda () -> Int:
            var m = Map[Int, Int]()
            for i in range(0, 100000):
                m.add(i, i)

            var n = 0
            for e in m.entries():
                n += e.value
            return n
    )

    bench(
        "set.add_contains",
        200000,
        lambda () -> Int:
            var s = Set[Int]()
            for i in range(0, 100000):
                s.add(i)

            var n = 0
            for i in range(0, 100000):
                if s.contains(i): n += 1
            return n
    )
