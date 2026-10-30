import keep, measure from "@std/bench.ms"
import words from "./src/harness.ms"

type Cell:
    x: Int
    y: Int

bench "map.int_put_get":
    fn work() Result[Unit, Error]:
        var m = Map[Int, Int]()
        for i in 0..100000:
            m.add(i, i * 2)

        var n = 0
        for i in 0..100000:
            n += m.get_or(i, 0)
        return keep(n)

    try measure(200000, work)

bench "map.record_key_get":
    fn work() Result[Unit, Error]:
        var m = Map[Cell, Int]()
        for i in 0..100000:
            m.add(Cell(x: i, y: i * 2), i)

        var n = 0
        for i in 0..100000:
            n += m.get_or(Cell(x: i, y: i * 2), 0)
        return keep(n)

    try measure(200000, work)

bench "map.string_put_get":
    fn work() Result[Unit, Error]:
        let keys = words(50000)
        var m = Map[String, Int]()
        for k in keys:
            m.add(k.clone(), 1)

        var n = 0
        for k in keys:
            n += m.get_or(k, 0)
        return keep(n)

    try measure(100000, work)

bench "map.get_let":
    fn work() Result[Unit, Error]:
        let keys = words(50000)
        var m = Map[String, String]()
        for k in keys:
            m.add(k.clone(), k.clone())

        var n = 0

        for k in keys:
            let found = m.get(k)
            if found.is_some():
                n += found.get().length()

        return keep(n)

    try measure(100000, work)

bench "map.get_if_let":
    fn work() Result[Unit, Error]:
        let keys = words(50000)
        var m = Map[String, String]()
        for k in keys:
            m.add(k.clone(), k.clone())

        var n = 0
        for k in keys:
            if let v = m.get(k):
                n += v.length()
        return keep(n)

    try measure(100000, work)

bench "map.get_chain":
    fn work() Result[Unit, Error]:
        let keys = words(50000)
        var m = Map[String, String]()
        for k in keys:
            m.add(k.clone(), k.clone())

        var n = 0
        for k in keys:
            n += m.get_or(k, "").length()
        return keep(n)

    try measure(100000, work)

bench "map.get_or":
    fn work() Result[Unit, Error]:
        let keys = words(50000)
        var m = Map[String, String]()
        for k in keys:
            m.add(k.clone(), k.clone())

        var n = 0
        for k in keys:
            n += m.get_or(key: k, fallback: "").length()
        return keep(n)

    try measure(100000, work)

bench "map.iterate_entries":
    fn work() Result[Unit, Error]:
        var m = Map[Int, Int]()
        for i in 0..100000:
            m.add(i, i)

        var n = 0
        for e in m.entries():
            n += e.value
        return keep(n)

    try measure(100000, work)

bench "set.add_contains":
    fn work() Result[Unit, Error]:
        var s = Set[Int]()
        for i in 0..100000:
            s.add(i)

        var n = 0
        for i in 0..100000:
            if s.contains(i): n += 1
        return keep(n)

    try measure(200000, work)
