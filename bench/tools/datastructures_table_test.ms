import operations, summarize, versions from "./datastructures_table.ms"
import repeats from "./lib.ms"
import expect_contains, expect_equal, expect_error, expect_ok from "@std/test/test.ms"

fn trial(version: String, per: Int) List[String]:
    var lines = List[String]()

    for op in operations():
        if version == "go" and op.name == "sorted_map_add_contains": continue

        lines.append("{version} {op.name} {op.count} {per * op.count}")

    lines.append("{version} # end")
    return lines

fn trials(per: Int) List[String]:
    var lines = List[String]()
    for v in versions():
        lines = lines.concat(trial(v, per))
    return lines

fn row(report: String, name: String) List[String]:
    for line in report.split("\n"):
        if line.starts_with(name + " "):
            let parts = line.split(" ").filter(fn p: p != "")
            return parts.slice(1, parts.length()).get([])

    return []

test "minimum and legitimately missing go operation":
    let lines = trials(100).concat(
        trial("go", 50)
    ).concat(trial("rs", 50)).concat(trial("ms", 50))
    let report = try expect_ok(summarize(lines, 2))
    try expect_contains(report, "Minimum of 2 rotating trials")
    try expect_equal(
        row(report, "list_append"), ["50.0", "50.0", "50.0", "1.00", "1.00"]
    )
    try expect_equal(
        row(report, "sorted_map_add_contains"), ["50.0", "-", "50.0", "-", "1.00"]
    )

test "zero samples stay visible without ratios":
    for zero in versions():
        var lines = List[String]()
        for v in versions():
            lines = lines.concat(trial(v, if v == zero: 0 else: 100))

        let found = row(try expect_ok(summarize(lines, 1)), "list_append")

        let at = if zero == "ms": 0 else: if zero == "go": 1 else: 2

        try expect_equal(found[at], "0.0")
        try expect_equal(found[3], if zero == "ms" or zero == "go": "-" else: "1.00")
        try expect_equal(found[4], if zero == "ms" or zero == "rs": "-" else: "1.00")

test "rejects invalid evidence":
    let good = trials(100)
    let rest = good.slice(1, good.length()).get([])
    let go_end = good.index_of("go # end").get(0)
    var cases = Map[String, List[String]]()
    cases.add("empty", List[String]())
    cases.add("unfinished", good.slice(0, good.length() - 1).get([]))
    cases.add("extra trial", good.concat(trial("ms", 100)))
    cases.add("missing everywhere", good.filter(fn l: not l.contains("list_append")))
    cases.add("duplicate", [good[0].clone()].concat(good))
    cases.add("missing version", good.filter(fn l: not l.starts_with("go ")))
    cases.add("missing boundary", good.filter(fn l: l != "ms # end"))
    cases.add(
        "unknown operation", [good[0].replace("list_append", "unknown")].concat(rest)
    )
    cases.add("unknown version", [good[0].replace("ms ", "unknown ")].concat(rest))
    cases.add(
        "unexpected go sorted map",
        good.slice(0, go_end).get([]).concat(
            ["go sorted_map_add_contains 600000 1"]
        ).concat(good.slice(go_end, good.length()).get([]))
    )
    cases.add("changed count", ["ms list_append 100000000 100000000"].concat(rest))
    cases.add("zero count", ["ms list_append 0 100000000"].concat(rest))
    cases.add("negative count", ["ms list_append -1000000 100000000"].concat(rest))
    cases.add("negative time", ["ms list_append 1000000 -1"].concat(rest))
    cases.add("noninteger time", ["ms list_append 1000000 nan"].concat(rest))
    cases.add("blank", good.concat([""]))
    for entry in cases.entries():
        let _cause = try expect_error(summarize(entry.value, 1))

    let _zero = try expect_error(summarize(good, 0))
    let _negative = try expect_error(summarize(good, -1))

test "a late bad sample produces no report":
    var lines = trials(100)
    lines[lines.length() - 2] = "rs sorted_map_add_contains 600000 -1"

    let cause = try expect_error(summarize(lines, 1))
    try expect_contains(cause.message(), "invalid count or timing")

test "invalid repeats are refused before building":
    for text in ["0", "00", "abc", "-1"]:
        let cause = try expect_error(repeats(text))
        try expect_contains(cause.message(), "repeats must be a positive integer")
