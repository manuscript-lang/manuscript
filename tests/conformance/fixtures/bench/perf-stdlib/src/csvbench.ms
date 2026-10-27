from "./harness.ms" import bench
from "@std/csv.ms" import parse, stringify

export def bench_csv() -> Unit:
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

    let csv_text = stringify(rows).get("")

    bench(
        "csv.stringify",
        5000,
        lambda () -> Int:
            if let s = stringify(rows):
                return s.length()

            return 0
    )

    bench(
        "csv.parse",
        5000,
        lambda () -> Int:
            if let r = parse(csv_text):
                return r.length()

            return 0
    )
