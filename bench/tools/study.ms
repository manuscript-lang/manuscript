# Building blocks for the per-experiment paired-trial drivers under bench/tools (names ending in a study topic). A study runs prebuilt
# producer binaries in rotating order, validates every record, and keeps samples, environment and a summary.
import (
    Invalid,
    absolute,
    dump,
    exists,
    file_sha256,
    invalid,
    jfloat,
    jobject,
    jstr,
    median,
    platform,
    read_text,
    sample,
    write_text
) from "./lib.ms"
import append_file, create_directory from "@std/os/fs.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"

# A labeled prebuilt binary.
export type Labeled:
    label: String
    path: String

export fn labeled(label: String, path: String) Labeled:
    return Labeled(label, absolute(path))

# Creates `path` and fails when it already exists (a study never overwrites earlier evidence).
export fn fresh_directory(path: String) Result[Unit, Invalid]:
    if exists(path): return invalid("{path} already exists")

    create_directory(path, recursive: true).get()
    return ok(unit)

# Trial order: rotated by the trial number and reversed on odd trials.
export fn trial_order(labels: List[String], trial: Int) List[String]:
    let n = labels.length()
    var order = List[String]()
    for i in 0..n:
        order.append(labels[(trial % n + i) % n].clone())
    if trial % 2 == 1: return order.reversed()

    return order

# Runs a producer and returns its integers.
export fn run_ints(path: String, args: List[String]) Result[List[Int], Invalid]:
    let text = try sample(path, args)
    let parts = text.replace("\n", " ").replace("\t", " ").split(" ").filter(
        fn p: (p != "")
    )
    var out = List[Int]()

    for part in parts:
        let n = part.parse_int()
        if n.is_none(): return invalid("not an integer: {part}")

        out.append(n.get(0))

    return ok(out)

export fn distribution(values: List[Float]) JsonValue:
    let m = median(values)
    var d = Map[String, JsonValue]()
    d.add("median_ns", jfloat(m))
    d.add("mad_ns", jfloat(median(values.map(fn v: if v > m: v - m else: m - v))))
    d.add(
        "min_ns",
        jfloat(
            values.fold(
                values[0], fn(a: Float, v: Float) Float: if v < a: v else: a
            )
        )
    )
    d.add(
        "max_ns",
        jfloat(
            values.fold(
                values[0], fn(a: Float, v: Float) Float: if v > a: v else: a
            )
        )
    )
    return jobject(d)

# One JSON line appended to `path`.
export fn append_json_line(path: String, value: JsonValue) Unit:
    append_file(path, stringify(value, none, none).get("") + "\n").get()

export fn write_json(path: String, value: JsonValue) Unit:
    write_text(path, dump(value))

# `{label: {path, sha256}}` for binaries.json / environment.json.
export fn binaries_json(items: List[Labeled]) JsonValue:
    var m = Map[String, JsonValue]()

    for b in items:
        var one = Map[String, JsonValue]()
        one.add("path", jstr(b.path.clone()))
        one.add("sha256", jstr(file_sha256(b.path)))
        m.add(b.label.clone(), jobject(one))

    return jobject(m)

# The parsed JSON file at `path`.
export fn read_json(path: String) Result[JsonValue, Invalid]:
    let doc = parse[JsonValue](read_text(path))
    if doc.is_error(): return invalid("{path} is not valid JSON")

    return ok(doc.get(JsonValue.Null))

# The `median_ns` of `before` in the summary row for `case` (summary lists `{case, distributions: {before: {median_ns}}}`).
export fn before_median(
    summary: JsonValue,
    name: String,
    operation: String
) Result[Float, Invalid]:
    for row in summary.as_list().get([]):
        let c = row.get("case").get(JsonValue.Null).as_string().get("")
        let op = row.get("operation")
        let same_op = (
            operation == ""
            or op.is_none()
            or op.get(JsonValue.Null).as_string().get("") == operation
        )
        if c == name and same_op:
            if let v = row.get_in(["distributions", "before", "median_ns"]):
                return ok(v.as_float().get(0.0))

    return invalid("no summary row for {name}")

export fn platform_name() String:
    return platform()

# Runs `binary args` and returns its standard output, pinned to one CPU with `taskset` (Linux) when `cpu` is not empty.
export fn run_pinned(
    binary: String,
    args: List[String],
    cpu: String
) Result[String, Invalid]:
    if cpu == "": return sample(binary, args)

    return sample("taskset", ["--cpu-list", cpu.clone(), binary.clone()].concat(args))

# Parses `values` as integers or fails.
export fn all_ints(values: List[String]) Result[List[Int], Invalid]:
    var out = List[Int]()

    for v in values:
        let n = v.trim().parse_int()
        if n.is_none(): return invalid("not an integer: {v}")

        out.append(n.get(0))

    return ok(out)

# How many rounds fill about 30 ms given one round took `elapsed` ns, within 1..100000.
export fn rounds_for(elapsed: Int) Int:
    let want = (30000000 + elapsed - 1) / elapsed
    if want < 1: return 1
    if want > 100000: return 100000

    return want
