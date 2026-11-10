import bench from "./harness.ms"
import parse, stringify from "@std/data/csv.ms"

export fn bench_csv() Unit:
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

    csv_text := stringify(rows).get("")

    bench(
        "csv.stringify",
        5000,
        fn() Int:
            if s := stringify(rows):
                return s.length()

            return 0
    )

    bench(
        "csv.parse",
        5000,
        fn() Int:
            if r := parse(csv_text):
                return r.length()

            return 0
    )
