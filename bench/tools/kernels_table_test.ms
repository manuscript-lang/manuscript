import (
    ablations,
    base_versions,
    c_versions,
    suite_names,
    summarize
) from "./kernels_table.ms"
import must, Ran from "./lib.ms"
import expect_contains, expect_equal, expect_error, expect_ok from "@std/test/test.ms"

fn trial(version: String, suite: String, micros: Int) List[String]:
    var lines = suite_names(suite).map(fn name: "{version} {name} {micros} 1")
    lines.append("{version} # end")
    return lines

fn trials(versions: List[String], suite: String, micros: Int) List[String]:
    var lines = List[String]()
    for v in versions:
        lines = lines.concat(trial(v, suite, micros))
    return lines

fn kernel_versions() List[String]:
    return base_versions().concat(c_versions())

test "complete rotating trials preserve minimum and columns":
    for suite in ["kernels", "competence"]:
        let versions = if suite == "kernels": kernel_versions() else: base_versions()

        var rotated = versions.slice(1, versions.length()).get([])
        rotated.append(versions[0].clone())

        let lines = trials(versions, suite, 100).concat(trials(rotated, suite, 50))
        let report = try expect_ok(summarize(lines, suite, 2, versions))
        try expect_contains(report, "Minimum of 2 rotating runs")
        try expect_contains(report, "| ms / rust | ms / rust-checked |")
        try expect_contains(report, "| {suite_names(suite)[0]} | 50 | 50 | 1.00x")

test "ablation versions and folded times":
    let versions = kernel_versions().concat(ablations())
    let report = try expect_ok(
        summarize(trials(versions, "kernels", 0), "kernels", 1, versions)
    )
    try expect_contains(report, "c-ms-unchecked us")
    try expect_contains(report, "folded")

test "rejects invalid evidence":
    let versions = kernel_versions()
    let good = trials(versions, "kernels", 100)
    let omitted = suite_names("kernels")[0]
    let last = good.length() - 1
    var truncated = good.clone()
    truncated.remove(last)

    var no_omitted = good.filter(fn l: not l.contains(omitted))
    var no_c = good.filter(fn l: not l.starts_with("c "))
    var cases = [
        List[String](),
        truncated,
        good.concat(trial("ms", "kernels", 100)),
        no_omitted,
        good.slice(1, good.length()).get([]),
        [good[0].clone()].concat(good),
        no_c,
        [good[0].replace("100", "-1")].concat(
            good.slice(1, good.length()).get([])
        ),
        [good[0].replace("100", "nan")].concat(
            good.slice(1, good.length()).get([])
        ),
        [good[0].replace(" 1", " 2")].concat(
            good.slice(1, good.length()).get([])
        ),
        [good[0].replace(omitted, "unknown")].concat(
            good.slice(1, good.length()).get([])
        ),
        [good[0].replace("go ", "unknown ")].concat(
            good.slice(1, good.length()).get([])
        ),
        ["go # end"].concat(good),
        good.concat(["unrecognized output"])
    ]
    for lines in cases:
        let _cause = try expect_error(summarize(lines, "kernels", 1, versions))

    let _zero = try expect_error(summarize(good, "kernels", 0, versions))
    let _short = try expect_error(summarize(good, "kernels", 1, base_versions()))

test "a late checksum mismatch produces no report":
    var lines = trials(kernel_versions(), "kernels", 100)
    lines[lines.length() - 2] = lines[lines.length() - 2].replace(" 1", " 2")

    let cause = try expect_error(summarize(lines, "kernels", 1, kernel_versions()))
    try expect_contains(cause.message(), "checksums differ")

test "a producer that fails or prints nothing is rejected":
    let failed = Ran(true, 42, "", "boom")
    let _failure = try expect_error(must("producer", failed))
    let missing = Ran(false, 125, "", "cannot start")
    let _start = try expect_error(must("producer", missing))
    let fine = Ran(true, 0, "ok", "")
    try expect_equal(try expect_ok(must("producer", fine)), "ok")

    let versions = kernel_versions()
    let empty = trials(versions.slice(0, 5).get([]), "kernels", 100)
    let _empty = try expect_error(summarize(empty, "kernels", 1, versions))
