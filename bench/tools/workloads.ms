// Realistic-program benchmark: builds the reference solutions of the small agent challenges (bench/agent/challenges/*/solutions)
// in Manuscript, Go and Rust, feeds each ~3 MB of its largest hidden stdin (repeated), checks that all three print identical
// output, and reports the minimum wall time in ms. Needs go and rustc on PATH. Unlike the kernels suite, these are ordinary
// parsing/string/map programs.
// Usage: ms run bench/tools/workloads.ms [-- repeats]; MS picks the compiler; BENCH_OUTPUT keeps the evidence directory.
import (
    absolute,
    capture,
    dump,
    ensure_directory,
    env,
    file_sha256,
    finish,
    invalid,
    jint,
    jlist,
    jobject,
    jstr,
    must,
    ms_binary,
    read_text,
    repeats,
    run_in,
    sample,
    usage,
    write_text from "./lib.ms",
    Measured, header, measure, row, versions from "./workloads_measure.ms",
    hex_encode from "@std/data/encoding.ms",
    sha256 from "@std/crypto.ms",
    JsonValue from "@std/data/json.ms",
    copy, create_directory, list, temporary from "@std/os/fs.ms",
    arguments from "@std/os/env.ms",
    parse from "@std/data/json.ms",
)

type Case:
    name: String
    stdin: String

fn largest_input(path: String) String!:
    cases := parse[List[Case]](read_text(path))
    if cases.is_error(): return invalid("cannot read {path}")

    var best = ""
    for c in cases.get([]):
        if c.stdin.length() > best.length(): best = c.stdin.clone()

    size := if not best.is_empty(): best.length() else: 1
    copies := if 3000000 / size > 1: 3000000 / size else: 1
    return ok(best.repeat(copies).get(""))

fn evidence(dir: String, name: String, n: Int, input: String, measured: Measured) Unit:
    var samples = List[JsonValue]()

    for s in measured.samples:
        var one = Map[String, JsonValue]()
        one.add("trial", jint(s.trial))
        one.add("version", jstr(s.version.clone()))
        one.add("elapsed_ns", jint(s.elapsed_ns))
        samples.append(jobject(one))

    var binaries = Map[String, JsonValue]()
    for v in versions():
        binaries.add(v.clone(), jstr(file_sha256("{dir}/{v}/app")))

    var doc = Map[String, JsonValue]()
    doc.add("name", jstr(name.clone()))
    doc.add("repeats", jint(n))
    doc.add("samples", jlist(samples))
    doc.add("input_sha256", jstr(hex_encode(sha256(input.to_bytes()))))
    doc.add("output_sha256", jstr(hex_encode(sha256(measured.expected.to_bytes()))))
    doc.add("binaries_sha256", jobject(binaries))
    write_text("{dir}/samples.json", dump(jobject(doc)))

fn run(work: String, n: Int) Result[String, Error]:
    var rows = [header()]
    root := "bench/agent/challenges"

    for entry in try list(root):
        if (
            not entry.name.starts_with("c")
            or not "01234".contains(entry.name.slice(1, 2).get("9"))
        ): continue

        name := entry.name.clone()
        dir := "{work}/{name}"
        source := "{root}/{name}"
        for sub in ["ms/src", "go", "rs"]:
            try create_directory("{dir}/{sub}", recursive: true)
        try copy("bench/agent/templates/ms/ms.toml", "{dir}/ms/ms.toml")
        try copy("{source}/solutions/ms/main.ms.ref", "{dir}/ms/src/main.ms")
        try copy("{source}/solutions/go/main.go.ref", "{dir}/go/main.go")
        try copy("{source}/solutions/rust/main.rs.ref", "{dir}/rs/main.rs")

        _mod := try must(
            "go mod init", run_in("{dir}/go", env("GO", "go"), ["mod", "init", "x"])
        )
        _go := try must(
            "go build",
            run_in(
                "{dir}/go", env("GO", "go"),
                ["build", "-buildvcs=false", "-o", "app", "."]
            )
        )
        _rs := try must(
            "rustc",
            capture(
                env("RUSTC", "rustc"), ["-O", "-o", "{dir}/rs/app", "{dir}/rs/main.rs"]
            )
        )
        _ms := try must(
            "ms build",
            run_in(
                "{dir}/ms", ms_binary(), ["build", "ms.toml", "-o", "app"]
            )
        )
        input := try largest_input("{source}/hidden/cases.json")
        measured := try measure(n, name, fn v: sample("{dir}/{v}/app", [], input))
        evidence(dir, name.clone(), n, input, measured)
        rows.append(row(name, measured.samples))

    // The table appears only once every workload has passed.
    write_text("{work}/table.txt", rows.join("\n") + "\n")
    return ok(rows.join("\n"))

fn main() Int:
    var n = 3
    args := arguments()

    if not args.is_empty():
        if parsed := repeats(args[0]):
            n = parsed
        else:
            return usage("repeats must be a positive integer")

    keep := env("BENCH_OUTPUT", "")

    if keep != "":
        ensure_directory(keep)
        return finish(run(absolute(keep), n))

    tmp := temporary("workloads-").get()
    return finish(run(tmp.path(), n))
