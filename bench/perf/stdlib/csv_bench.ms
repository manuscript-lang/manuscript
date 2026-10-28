from "@std/bench.ms" import keep, measure
from "@std/csv.ms" import parse, stringify

bench "csv.stringify":
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

    def work() -> Result[Unit, Error]:
        if let s = stringify(rows):
            return keep(s.length())

        return keep(0)

    try measure(5000, work)

bench "csv.parse":
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append([f"{i}", f"name {i}", "a,b", "quote\"d"])

    let csv_text = stringify(rows).get("")

    def work() -> Result[Unit, Error]:
        if let r = parse(csv_text):
            return keep(r.length())

        return keep(0)

    try measure(5000, work)
