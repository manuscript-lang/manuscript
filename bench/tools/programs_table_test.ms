import SINK, ops, summarize from "./programs_table.ms"
import expect_contains, expect_equal, expect_error from "@std/test.ms"

fn sample(version: String) List[String]:
    var lines = ops().map(fn op: "{version} {op.name} {op.count} {op.count * 2}")
    lines.append("{version} # sink " + SINK.map(fn n: "{n}").join(" "))
    return lines

fn both() List[String]:
    return sample("ms").concat(sample("go"))

test "complete equivalent work":
    let result = try summarize(both(), 1)
    try expect_contains(result, "1.00x")
    try expect_contains(result, "Checksums and operation counts verified")

test "extra versions add columns":
    let lines = both().concat(sample("rust")).concat(sample("rust-checked"))
    let result = try summarize(lines, 1)
    try expect_contains(
        result,
        "| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |"
    )
    try expect_equal(result.split("1.00x").length() - 1, 3 * ops().length())

test "rejects invalid evidence":
    let valid = both()
    let last = valid.length() - 1
    var cut = valid.clone()
    cut.remove(last)

    var doubled = valid.clone()
    doubled = doubled.concat(sample("ms"))

    var short_count = valid.clone()
    short_count[0] = short_count[0].replace("50000 100000", "1 100000")

    var zero_time = valid.clone()
    zero_time[0] = zero_time[0].replace("100000", "0")

    var bad_sink = valid.clone()
    bad_sink[last] = bad_sink[last].replace("50000", "49999")

    let extra_first = [valid[0].clone()].concat(valid)
    let junk = ["unrecognized output"].concat(valid)
    for lines in [cut, doubled, short_count, zero_time, bad_sink, extra_first, junk]:
        let _cause = try expect_error(summarize(lines, 1))
