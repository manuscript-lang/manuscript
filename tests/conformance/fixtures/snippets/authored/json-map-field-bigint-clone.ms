# conform: tags=maps,records,stdlib-json,stdlib-bigint,stdlib-testing,testing
# conform: phase=test
import expect_equal from "@std/test/test.ms"
import stringify, parse from "@std/data/json.ms"
import from_int from "@std/math/math.ms"

type Report:
    name: String
    scores: Map[String, Int]

test "a record with a Map[String, T] field is Data and roundtrips as a JSON object":
    var scores = Map[String, Int]()
    scores["a"] = 1
    let text = try stringify(Report(name: "x", scores: scores))
    try expect_equal(text, "\{\"name\":\"x\",\"scores\":\{\"a\":1\}\}")
    let back = try parse[Report](text)
    try expect_equal(back.scores["a"], 1)

test "BigInt clone starts an independent accumulator":
    let base = from_int(5)
    var acc = base.clone()
    acc = acc + base
    try expect_equal(acc, from_int(10))
    try expect_equal(base, from_int(5))
