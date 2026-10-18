import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {parse, stringify} from "@std/csv.ms"

export fn bench_csv() Unit:
    let rows: List[List[String]] = []
    for i in range(0, 5000):
        rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

    let csv_text = match stringify(rows: rows):
        ok(s): s
        error(_): ""

    bench(
        "csv.stringify",
        5000,
        fn() Int:
            match stringify(rows: rows):
                ok(s): return s.length()
                error(_): return 0
    )
    bench(
        "csv.parse",
        5000,
        fn() Int:
            match parse(text: csv_text):
                ok(r): return r.length()
                error(_): return 0
    )
