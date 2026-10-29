import {bench, words} from "./harness.ms"

export fn bench_map_set() Unit:
    bench(
        "map.int_put_get",
        200000,
        fn() Int:
            var m = Map[Int, Int]()
            for i in 0..100000:
                m.add(i, i * 2)

            var n = 0
            for i in 0..100000:
                n += m.get(i).get(0)
            return n
    )

    bench(
        "map.string_put_get",
        100000,
        fn() Int:
            let keys = words(50000)
            var m = Map[String, Int]()
            for k in keys:
                m.add(k, 1)

            var n = 0
            for k in keys:
                n += m.get(k).get(0)
            return n
    )

    bench(
        "map.iterate_entries",
        100000,
        fn() Int:
            var m = Map[Int, Int]()
            for i in 0..100000:
                m.add(i, i)

            var n = 0
            for e in m.entries():
                n += e.value
            return n
    )

    bench(
        "set.add_contains",
        200000,
        fn() Int:
            var s = Set[Int]()
            for i in 0..100000:
                s.add(i)

            var n = 0
            for i in 0..100000:
                if s.contains(i): n += 1
            return n
    )
