import {bench} from "./harness.ms"
import {parse, stringify} from "@std/csv.ms"

export fn bench_csv() -> Unit:
    let rows: List[List[String]] = []
    var i = 0

    while i < 5000:
        rows.append(["{i}", "name {i}", "a,b", "quote\"d"])
        i = i + 1

    let csv_text = stringify(rows: rows).unwrap_or("")
    bench(
        "csv.stringify",
        5000,
        fn() -> Int:
            if let s = stringify(rows: rows): return s.length()

            return 0
    )
    bench(
        "csv.parse",
        5000,
        fn() -> Int:
            if let r = parse(text: csv_text): return r.length()

            return 0
    )
