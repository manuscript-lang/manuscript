import range from "@std/collections.ms"
import {bench, words} from "./harness.ms"

export fn bench_map_set() Unit:
    bench(
        "map.int_put_get",
        200000,
        fn() Int:
            let m = Map[Int, Int]()
            for i in range(0, 100000):
                m.add(key: i, value: i * 2)
            var n = 0
            for i in range(0, 100000):
                n = n + m.get(key: i).unwrap_or(0)
            return n
    )
    bench(
        "map.string_put_get",
        100000,
        fn() Int:
            let keys = words(50000)
            let m = Map[String, Int]()
            for k in keys:
                m.add(key: k, value: 1)
            var n = 0
            for k in keys:
                n = n + m.get(key: k).unwrap_or(0)
            return n
    )
    bench(
        "map.iterate_entries",
        100000,
        fn() Int:
            let m = Map[Int, Int]()
            for i in range(0, 100000):
                m.add(key: i, value: i)
            var n = 0
            for e in m.entries():
                n = n + e.value
            return n
    )
    bench(
        "set.add_contains",
        200000,
        fn() Int:
            let s = Set[Int]()
            for i in range(0, 100000):
                s.add(i)
            var n = 0
            for i in range(0, 100000):
                if s.contains(i): n = n + 1
            return n
    )
