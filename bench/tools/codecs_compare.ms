// Pairs existing generated executables (bench/perf/codecs, bench/perf/codecs/json-failure); only their internal timer is measured.
// Usage: ms run bench/tools/codecs_compare.ms -- <decode|json-failure> BEFORE AFTER OUTPUT_DIR [--pairs 9]
// `decode` harness: `size count rounds` -> `size count rounds checksum elapsed_ns`.
// `json-failure` harness: `size rounds shape` -> `size rounds shape rounds_checksum wall_ns cpu_ns`.
// Pair -1 is an untimed warm-up and is excluded from the printed summary.
import (
    absolute,
    fail,
    invalid,
    jfloat,
    jint,
    jobject,
    jstr,
    jbool,
    median,
    options,
    write_text
) from "./lib.ms"
import (
    all_ints,
    append_json_line,
    binaries_json,
    fresh_directory,
    labeled,
    run_pinned,
    write_json
) from "./study.ms"
import arguments from "@std/os/env.ms"
import JsonValue from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

type Decode:
    size: Int
    count: Int
    rounds: Int

type Failure:
    size: Int
    rounds: Int
    shape: String

fn decode_cases() List[Decode]:
    return [
        Decode(0, 1000, 500), Decode(1, 1000, 500), Decode(3, 1000, 500),
        Decode(32, 1000, 300), Decode(1024, 100, 50), Decode(65536, 1, 100),
        Decode(3, 1, 100000)
    ]

fn failure_cases() List[Failure]:
    var out = List[Failure]()

    for shape in ["plain", "escaped", "typed-plain", "typed-escaped"]:
        for size in [0, 16, 1024, 65536, 1048576]:
            rounds := if size <= 16: 300000 else: (
                if size == 1024: 20000 else: (
                    if size == 65536: 1000 else: 500
                )
            )
            out.append(Failure(size, rounds, shape.clone()))

    for shape in ["valid", "typed-valid"]:
        for size in [0, 16, 1024]:
            out.append(Failure(size, if size <= 16: 100000 else: 10000, shape.clone()))
    return out

fn stats_line(label: String, values: List[Float]) String:
    low := values.fold(values[0], fn(a: Float, v: Float) Float: if v < a: v else: a)
    high := values.fold(values[0], fn(a: Float, v: Float) Float: if v > a: v else: a)
    return "{label} [{low.to_fixed(3)},{high.to_fixed(3)}] {median(values).to_fixed(3)}"

fn triple(values: List[Float]) String:
    low := values.fold(values[0], fn(a: Float, v: Float) Float: if v < a: v else: a)
    high := values.fold(values[0], fn(a: Float, v: Float) Float: if v > a: v else: a)
    return "{low} {median(values)} {high}"

fn decode(before: String, after: String, out: String, pairs: Int) Result[Unit, Error]:
    try fresh_directory(out)

    var paths = Map[String, String]()
    paths.add("before", before.clone())
    paths.add("after", after.clone())
    write_json(
        "{out}/binaries.json",
        binaries_json([labeled("before", before), labeled("after", after)])
    )
    write_text("{out}/samples.jsonl", "")

    for c in decode_cases():
        key := "{c.size}/{c.count}/{c.rounds}"
        var samples = Map[String, List[Float]]()
        samples.add("before", List[Float]())
        samples.add("after", List[Float]())

        for pair in - 1..pairs:
            for name in (
                if pair % 2 == 0: ["before", "after"] else: [
                    "after", "before"
                ]
            ):
                text := try run_pinned(
                    paths.get(name).get(""), ["{c.size}", "{c.count}", "{c.rounds}"], ""
                )
                parts := text.replace("\n", " ").split(" ").filter(fn p: p != "")
                if parts.length() != 5: return invalid("invalid output {name}: {text}")

                observed := try all_ints(parts)
                if (
                    observed[0] != c.size
                    or observed[1] != c.count
                    or observed[2] != c.rounds
                    or observed[3] != c.size * c.count * c.rounds
                    or observed[4] <= 0
                ):
                    return invalid("wrong identity/checksum/timer: {observed}")

                elapsed := observed[4].to_float() / c.rounds.to_float()
                var row = Map[String, JsonValue]()
                row.add("case", jstr(key.clone()))
                row.add("pair", jint(pair))
                row.add("label", jstr(name.clone()))
                row.add("checksum", jint(observed[3]))
                row.add("ns_per_parse", jfloat(elapsed))
                append_json_line("{out}/samples.jsonl", jobject(row))

                if pair >= 0:
                    var list = samples.get(name).get([])
                    list.append(elapsed)
                    samples.add(name.clone(), list)

        b := samples.get("before").get([])
        a := samples.get("after").get([])
        (
            stdout()
            .write(
                "{key} before {triple(b)} after {triple(a)} ratio {median(a) / median(b)}\n"
            )
            .get()
        )

    return ok(unit)

fn json_failure(
    before: String,
    after: String,
    out: String,
    pairs: Int
) Result[Unit, Error]:
    try fresh_directory(out)

    var paths = Map[String, String]()
    paths.add("before", before.clone())
    paths.add("after", after.clone())

    cases := failure_cases()
    var manifest = Map[String, JsonValue]()
    manifest.add("complete", jbool(false))
    manifest.add("pairs", jint(pairs))
    manifest.add(
        "binaries", binaries_json([labeled("before", before), labeled("after", after)])
    )
    write_json("{out}/manifest.json", jobject(manifest.clone()))
    write_text("{out}/samples.jsonl", "")

    var summary = List[String]()

    for c in cases:
        var wall = Map[String, List[Float]]()
        var cpu = Map[String, List[Float]]()

        for name in ["before", "after"]:
            wall.add(name.clone(), List[Float]())
            cpu.add(name.clone(), List[Float]())

        for repeat in - 1..pairs:
            for name in (
                if repeat % 2 == 0: ["before", "after"] else: [
                    "after", "before"
                ]
            ):
                text := try run_pinned(
                    paths.get(name).get(""),
                    ["{c.size}", "{c.rounds}", c.shape.clone()], ""
                )
                fields := text.replace("\n", " ").split(" ").filter(fn p: p != "")
                if (
                    fields.length() != 6
                    or fields[0] != "{c.size}"
                    or fields[1] != "{c.rounds}"
                    or fields[2] != c.shape
                    or fields[3] != "{c.rounds}"
                ):
                    return invalid("invalid identity/checksum/timer: {name}: {text}")

                nums := try all_ints(fields.slice(3, 6).get([]))
                if nums[1] <= 0 or nums[2] <= 0: return invalid(
                    "invalid identity/checksum/timer: {name}: {text}"
                )

                w := nums[1].to_float() / c.rounds.to_float()
                u := nums[2].to_float() / c.rounds.to_float()
                var row = Map[String, JsonValue]()
                row.add("size", jint(c.size))
                row.add("rounds", jint(c.rounds))
                row.add("shape", jstr(c.shape.clone()))
                row.add("repeat", jint(repeat))
                row.add("label", jstr(name.clone()))
                row.add("checksum", jint(nums[0]))
                row.add("wall_ns", jfloat(w))
                row.add("cpu_ns", jfloat(u))
                append_json_line("{out}/samples.jsonl", jobject(row))

                if repeat >= 0:
                    var wl = wall.get(name).get([])
                    wl.append(w)
                    wall.add(name.clone(), wl)

                    var cl = cpu.get(name).get([])
                    cl.append(u)
                    cpu.add(name.clone(), cl)

        summary.append(
            "{c.shape} {c.size} wall_ns: before {stats_line("", wall.get("before").get([]))} after {stats_line("", wall.get("after").get([]))}"
        )
        summary.append(
            "{c.shape} {c.size} cpu_ns: before {stats_line("", cpu.get("before").get([]))} after {stats_line("", cpu.get("after").get([]))}"
        )

    manifest.add("complete", jbool(true))
    manifest.add("producer_executions", jint(cases.length() * 2 * (pairs + 1)))
    write_json("{out}/manifest.json", jobject(manifest))
    stdout().write(summary.join("\n") + "\n").get()
    return ok(unit)

export fn main() Int:
    args := arguments()
    if args.length() < 4 or not ["decode", "json-failure"].contains(args[0]):
        return fail(
            "usage: codecs_compare.ms -- <decode|json-failure> BEFORE AFTER OUTPUT_DIR [--pairs N]"
        )

    parsed := options(args.slice(4, args.length()).get([]), ["pairs"], [])
    if parsed.is_error(): return fail(parsed.err().message)

    pairs := parsed.get(
        Map[String, String]()
    ).get("pairs").get("9").parse_int().get(0)
    if pairs < 2: return fail("at least two pairs required")

    before := absolute(args[1].clone())
    after := absolute(args[2].clone())
    result := if args[0] == "decode": decode(before, after, args[3].clone(), pairs) else: json_failure(
        before, after, args[3].clone(), pairs
    )
    if result.is_error(): return fail(result.err().message)

    return 0
