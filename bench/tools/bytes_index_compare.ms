# Validates and compares already-built byte-search programs in balanced order (bench/perf/bytes-index).
# Usage: ms run bench/tools/bytes_index_compare.ms -- BEFORE AFTER RUST OUTPUT_DIR [--cpu N]
# Programs print the string-lines CSV (see string_lines_compare.ms). Expected checksums come from a straightforward search of a
# buffer of `a` bytes holding one 0xFF byte, an oracle independent of the programs. --cpu pins every run with `taskset`.
import Identity, run_rows from "./string_lines_compare.ms"
import (
    absolute,
    fail,
    jbool,
    jint,
    jlist,
    jobject,
    jstr,
    median,
    options,
    permutations,
    platform,
    write_text
) from "./lib.ms"
import binaries_json, fresh_directory, labeled, write_json from "./study.ms"
import arguments from "@std/os/process.ms"
import JsonValue from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

fn sizes() List[Int]:
    return [0, 1, 7, 15, 31, 32, 64, 256, 4096, 1048576]

fn kinds() List[String]:
    return [
        "miss", "first", "middle", "last", "negative", "past", "equal", "offset",
        "near1", "near7", "near8", "near9", "near15", "near16", "near17", "near18",
        "near23", "near24", "near25", "near31", "near32", "near33"
    ]

# The expected (size, iterations, checksum) of every case.
fn identities() Map[String, Identity]:
    var rows = Map[String, Identity]()

    for size in sizes():
        for kind in kinds():
            var position = -1
            var start = 0
            if kind == "first" or kind == "negative" or kind == "past": position = 0

            if kind.starts_with("near"):
                let want = kind.slice(4, kind.length()).get("0").parse_int().get(0)
                position = if want < size - 1: want else: size - 1

            if kind == "middle": position = size / 2
            if kind == "last" or kind == "offset": position = size - 1
            if kind == "negative": start = -1
            if kind == "past": start = size + 1
            if kind == "equal": start = size
            if kind == "offset": start = size / 2

            let from = if start > 0: start else: 0

            # The first 0xFF at or after `from`, or -1.
            let found = if position >= 0 and position < size and position >= from: position else: -1
            let expected = if found == -1: size else: found
            var work = size
            if expected < size: work = expected + 1 - start
            if start < 0: work = expected + 1
            if start >= size: work = 1

            let divisor = if work > 32: work else: 32
            let by_work = 67108864 / divisor
            let iterations = if by_work < 256: 256 else: (
                if by_work > 1000000: 1000000 else: by_work
            )
            rows.add("{kind}_{size}", Identity(size, iterations, expected * iterations))

    return rows

fn run(paths: Map[String, String], out: String, cpu: String) Result[Unit, Error]:
    try fresh_directory(out)

    let expected = identities()
    let names = ["before", "after", "rust"]
    let orders = permutations(names)
    var csv = ["pair,variant,case,input_bytes,iterations,elapsed_ns,checksum"]
    var validated = List[JsonValue]()
    var complete = false
    var per = Map[String, List[Float]]()

    for name in names:
        let _warm = try run_rows(paths.get(name).get(""), expected, cpu)
        validated.append(jstr("warmup {name}"))

    for pair in 0..orders.length():
        for variant in orders[pair]:
            for row in try run_rows(paths.get(variant).get(""), expected, cpu):
                csv.append("{pair},{variant},{row.line}")

                let key = "{row.name} {variant}"
                var list = per.get(key).get([])
                list.append(row.elapsed_ns.to_float() / row.iterations.to_float())
                per.add(key.clone(), list)

            validated.append(jstr("{pair} {variant}"))

    complete = true

    var record = Map[String, JsonValue]()
    record.add("complete", jbool(complete))
    record.add("platform", jstr(platform()))
    record.add("cpu", jstr(cpu))
    record.add("expected_cases", jint(expected.length()))
    record.add(
        "executables",
        binaries_json(names.map(fn n: labeled(n.clone(), paths.get(n).get(""))))
    )
    record.add("validated_producers", jlist(validated))
    write_json("{out}/record.json", jobject(record))
    write_text("{out}/samples.csv", csv.join("\n") + "\n")

    var rows = [
        "case,before_median_ns,before_min_ns,before_max_ns,after_median_ns,after_min_ns,after_max_ns,rust_median_ns,rust_min_ns,rust_max_ns,paired_delta_median_ns,pairs_slower"
    ]

    for name in expected.keys():
        var cells = List[String]()

        for variant in names:
            let s = per.get("{name} {variant}").get([])
            let sorted = s.sorted()
            cells = cells.concat(
                [
                    "{median(s)}", "{sorted[0]}", "{sorted[sorted.length() - 1]}"
                ]
            )

        let b = per.get("{name} before").get([])
        let a = per.get("{name} after").get([])
        var deltas = List[Float]()
        var slower = 0

        for i in 0..b.length():
            deltas.append(a[i] - b[i])
            if a[i] - b[i] > 0.0: slower += 1

        rows.append("{name},{cells.join(",")},{median(deltas)},{slower}")

    write_text("{out}/summary.csv", rows.join("\n") + "\n")
    (
        stdout().write(
            "{expected.length()} cases, {orders.length()} orders, {out}/summary.csv\n"
        ).get()
    )
    return ok(unit)

export fn main() Int:
    let args = arguments()
    if args.length() < 4: return fail(
        "usage: bytes_index_compare.ms -- BEFORE AFTER RUST OUTPUT_DIR [--cpu N]"
    )

    let parsed = options(args.slice(4, args.length()).get([]), ["cpu"], [])
    if parsed.is_error(): return fail(parsed.err().message())

    var paths = Map[String, String]()
    paths.add("before", absolute(args[0].clone()))
    paths.add("after", absolute(args[1].clone()))
    paths.add("rust", absolute(args[2].clone()))

    let result = run(
        paths, args[3].clone(), parsed.get(Map[String, String]()).get("cpu").get("")
    )
    if result.is_error(): return fail(result.err().message())

    return 0
