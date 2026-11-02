# Compares two `ms` builds on the bench/perf/stdlib bench blocks, alternating runs and checking the cases match.
# Usage: ms run bench/tools/compare_stdlib.ms -- --before MS --after MS --output DIR [--repeats 5] [--samples 5] [--filter TEXT]
import (
    absolute,
    dump,
    ensure_directory,
    fail,
    file_sha256,
    finish,
    invalid,
    jfloat,
    jint,
    jobject,
    jstr,
    median,
    options,
    platform,
    stdlib_bench,
    write_text
) from "./lib.ms"
import Stats, case_labels, read_cases from "./stdlib_results.ms"
import arguments from "@std/os/process.ms"
import JsonValue from "@std/data/json.ms"

# One document as `{case: operations}` and `{case: median ns/op}`.
export type Sample:
    operations: Map[String, Int]
    medians: Map[String, Float]

export fn parse_sample(output: String, expected: Map[String, Int]?) Sample!:
    let cases = try read_cases(output)
    var operations = Map[String, Int]()
    var medians = Map[String, Float]()

    for c in cases:
        let stats = c.stats.get(Stats(0, none, none, 0.0, none, none, none, none))
        operations.add(c.name.clone(), stats.operations)
        medians.add(c.name.clone(), stats.median_ns)

    if let want = expected:
        if want != operations: return invalid("cases or operation counts changed")
    return ok(Sample(operations, medians))

fn run(opts: Map[String, String], repeats: Int, samples: Int) Result[String, Error]:
    let filter = opts.get("filter").get("")
    var binaries = Map[String, String]()
    var raw = Map[String, List[String]]()
    var values = Map[String, Map[String, List[Float]]]()

    for name in ["before", "after"]:
        binaries.add(name.clone(), absolute(opts.get(name).get("")))
        raw.add(name.clone(), List[String]())
        values.add(name.clone(), Map[String, List[Float]]())

    var expected: Map[String, Int]? = none
    var names = List[String]()

    for i in 0..repeats:
        for version in (if i % 2 == 0: ["before", "after"] else: ["after", "before"]):
            let output = try stdlib_bench(
                binaries.get(version).get(""), samples, filter
            )
            let parsed = try parse_sample(output, expected)

            if expected.is_none():
                expected = parsed.operations.clone()
                names = parsed.operations.keys()

            var kept = raw.get(version).get([])
            kept.append(output.trim() + "\n")
            raw.add(version.clone(), kept)

            var per = values.get(version).get(Map[String, List[Float]]())

            for entry in parsed.medians.entries():
                var list = per.get(entry.key).get([])
                list.append(entry.value)
                per.add(entry.key.clone(), list)

            values.add(version.clone(), per)

    let want = expected.get(Map[String, Int]())
    let labels = case_labels(names)
    var table = [
        "Median of {repeats} alternating runs of {samples} samples; all {want.length()} cases and operation counts verified.",
        "", "| operation | ops | before ns/op | after ns/op | after/before |",
        "|---|---:|---:|---:|---:|"
    ]
    var summary = Map[String, JsonValue]()

    for name in names:
        let before = median(
            values.get("before").get(Map[String, List[Float]]()).get(
                name
            ).get([])
        )
        let after = median(
            values.get("after").get(Map[String, List[Float]]()).get(
                name
            ).get([])
        )
        var ratio: Float? = none
        if before != 0.0: ratio = after / before

        let label = labels.get(name).get(name)
        let ops = want.get(name).get(0)
        var entry = Map[String, JsonValue]()
        entry.add("ops", jint(ops))
        entry.add("before", jfloat(before))
        entry.add("after", jfloat(after))
        entry.add(
            "ratio", if ratio.is_some(): jfloat(ratio.get(0.0)) else: JsonValue.Null
        )
        summary.add(label.clone(), jobject(entry))

        var shown = "—"
        if let r = ratio: shown = r.to_fixed(3) + "x"
        table.append(
            "| {label} | {ops} | {before.to_precision(4)} | {after.to_precision(4)} | {shown} |"
        )

    let out = opts.get("output").get("")
    ensure_directory(out)
    for version in ["before", "after"]:
        write_text("{out}/stdlib-{version}.jsonl", raw.get(version).get([]).join(""))

    var shas = Map[String, JsonValue]()

    for version in ["before", "after"]:
        var binary = Map[String, JsonValue]()
        binary.add("path", jstr(binaries.get(version).get("")))
        binary.add("sha256", jstr(file_sha256(binaries.get(version).get(""))))
        shas.add(version.clone(), jobject(binary))

    var environment = Map[String, JsonValue]()
    environment.add("platform", jstr(platform()))
    environment.add("repeats", jint(repeats))
    environment.add("samples", jint(samples))
    environment.add("binaries", jobject(shas))
    write_text("{out}/environment.json", dump(jobject(environment)))
    write_text("{out}/summary.json", dump(jobject(summary)))

    let rendered = table.join("\n") + "\n"
    write_text("{out}/results.md", rendered)
    return ok(rendered)

export fn main() Int:
    let parsed = options(
        arguments(), ["before", "after", "output", "repeats", "samples", "filter"],
        ["before", "after", "output"]
    )
    if parsed.is_error(): return fail(parsed.err().message)

    let opts = parsed.get(Map[String, String]())
    let repeats = opts.get("repeats").get("5").parse_int().get(0)
    let samples = opts.get("samples").get("5").parse_int().get(0)
    if repeats < 1 or samples < 1: return fail("repeats and samples must be positive")

    return finish(run(opts, repeats, samples))
