import {keep, measure} from "@std/bench.ms"
import {parse, stringify} from "@std/csv.ms"

bench "csv.stringify":
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

    fn work() Result[Unit, Error]:
        if let s = stringify(rows):
            return keep(s.length())

        return keep(0)

    try measure(5000, work)

bench "csv.parse":
    var rows: List[List[String]] = []
    for i in 0..5000:
        rows.append(["{i}", "name {i}", "a,b", "quote\"d"])

    let csv_text = stringify(rows).get("")

    fn work() Result[Unit, Error]:
        if let r = parse(csv_text):
            return keep(r.length())

        return keep(0)

    try measure(5000, work)
