import parse_sample from "./compare_stdlib.ms"
import stdlib_table from "./stdlib_bench.ms"
import Stats, case_labels, read_cases from "./stdlib_results.ms"
import must, Ran from "./lib.ms"
import expect_contains, expect_equal, expect_error, expect_ok from "@std/test/test.ms"

fn bench(name: String, status: String, ops: String, median: String) String:
    return j(
        "<'name':'m.ms::{name}','status':'{status}','stats':<'operations':{ops},'median_ns':{median}>>"
    )

fn j(text: String) String:
    return text.replace("'", "\"").replace("<", "\{").replace(">", "\}")

fn document(cases: List[String]) String:
    return j("<'benches':[{cases.join(",")}],'diagnostics':[]>")

test "invalid numeric fields are rejected":
    let texts = [
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':'2'>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':-1>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':1,'samples':3,'median_ns':null>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':0,'median_ns':2>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':1.5,'median_ns':2>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'iterations':0,'median_ns':2>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'samples':true,'median_ns':2>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'median_ns':2,'min_ns':-1>>]>"
        ),
        j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':10,'median_ns':2,'min_ns':1,'max_ns':1>>]>"
        )
    ]
    for text in texts:
        let _cause = try expect_error(read_cases(text))

test "huge exponents and non-finite constants are rejected, finite zero is not":
    for token in ["1e999", "NaN", "Infinity", "-Infinity"]:
        let text = j(
            "<'benches':[<'name':'a','status':'passed','stats':<'operations':1,'median_ns':{token}>>]>"
        )
        let _cause = try expect_error(read_cases(text))

    let cases = try expect_ok(
        read_cases(
            j(
                "<'benches':[<'name':'a','status':'passed','stats':<'operations':1,'median_ns':0>>]>"
            )
        )
    )
    try expect_equal(
        cases[0].stats.get(
            Stats(0, none, none, -1.0, none, none, none, none)
        ).median_ns,
        0.0
    )

test "labels disambiguate only collisions":
    let labels = case_labels(["a.ms::x", "b.ms::x", "b.ms::y"])
    try expect_equal(labels.get("a.ms::x").get(""), "a.ms::x")
    try expect_equal(labels.get("b.ms::x").get(""), "b.ms::x")
    try expect_equal(labels.get("b.ms::y").get(""), "y")

test "a user label cannot collide with a qualified display name":
    let names = ["a.ms::x", "b.ms::x", "c.ms::a.ms::x"]
    let labels = case_labels(names)
    for name in names:
        try expect_equal(labels.get(name).get(""), name)

test "reads operations and median per case":
    let sample = try expect_ok(
        parse_sample(
            document(
                [
                    bench("a", "passed", "10", "2.5"), bench("b", "passed", "1", "0")
                ]
            ),
            none
        )
    )
    try expect_equal(sample.operations.get("m.ms::a").get(0), 10)
    try expect_equal(sample.medians.get("m.ms::a").get(0.0), 2.5)
    try expect_equal(sample.medians.get("m.ms::b").get(1.0), 0.0)

test "qualified case identity":
    let before = document([bench("a", "passed", "10", "2")])
    let first = try expect_ok(parse_sample(before, none))
    let other = before.replace("m.ms::a", "other.ms::a")
    let _changed = try expect_error(parse_sample(other, first.operations.clone()))
    let both = try expect_ok(
        parse_sample(
            document(
                [
                    bench("a", "passed", "10", "2"),
                    j(
                        "<'name':'other.ms::a','status':'passed','stats':<'operations':10,'median_ns':2>>"
                    )
                ]
            ),
            none
        )
    )
    try expect_equal(both.operations.length(), 2)

test "changed cases or operation counts are rejected":
    let first = try expect_ok(
        parse_sample(document([bench("a", "passed", "10", "2")]), none)
    )
    let changes = [
        document([bench("a", "passed", "11", "2")]),
        document([bench("b", "passed", "10", "2")]),
        document(
            [
                bench("a", "passed", "10", "2"), bench("b", "passed", "1", "2")
            ]
        )
    ]
    for text in changes:
        let _cause = try expect_error(parse_sample(text, first.operations.clone()))

test "failed, duplicate, empty or uncompiled runs are rejected":
    let texts = [
        document([bench("a", "failed", "10", "2")]),
        document(
            [
                bench("a", "passed", "10", "2"), bench("a", "passed", "10", "2")
            ]
        ),
        document([]),
        j("<'benches':[],'diagnostics':[<'message':'does not compile'>]>")
    ]
    for text in texts:
        let _cause = try expect_error(parse_sample(text, none))

test "impossible measurements are rejected":
    for text in [
        document([bench("a", "passed", "0", "2")]),
        document([bench("a", "passed", "10", "-1")])
    ]:
        let _cause = try expect_error(parse_sample(text, none))

test "a failed producer yields no report":
    let failed = Ran(
        true, 42, "{document([bench("a", "passed", "10", "2")])}", "producer detail"
    )
    let _cause = try expect_error(must("producer", failed))
    let empty = try expect_error(stdlib_table(document([])))
    try expect_contains(empty.message, "no cases")
