// Builds checked native workloads (bench/language/*.ms) with two Manuscript CLIs and compares them, alternating the first runner.
// Usage: ms run bench/tools/language_benchmark.ms -- --before MS --after MS --output DIR [--runs 3] [--cpu N]
// --cpu pins every execution to one CPU through `taskset` (Linux).
import (
    absolute,
    capture,
    dump,
    ensure_directory,
    fail,
    finish,
    jfloat,
    jint,
    jlist,
    jobject,
    jstr,
    median,
    must,
    now_ns,
    options,
    platform,
    write_text from "./lib.ms",
    arguments from "@std/os/env.ms",
    JsonValue from "@std/data/json.ms",
    stdout from "@std/io/io.ms",
)

fn execute(binary: String, cpu: String) Result[Unit, Error]:
    if cpu == "":
        _ := try must(binary, capture(binary, []))
        return ok(unit)

    _ := try must(binary, capture("taskset", ["-c", cpu.clone(), binary.clone()]))

fn run(opts: Map[String, String], runs: Int) Result[String, Error]:
    out := absolute(opts.get_or("output", ""))
    ensure_directory(out)

    cpu := opts.get_or("cpu", "")
    var clis = Map[String, String]()
    clis.add("before", absolute(opts.get_or("before", "")))
    clis.add("after", absolute(opts.get_or("after", "")))

    workloads := ["numeric", "calls", "list", "life"]

    for name in workloads:
        for label in ["before", "after"]:
            cli := clis.get_or(label, "")
            source := "bench/language/{name}.ms"
            _bin := try must(
                "ms build {name}",
                capture(
                    cli.clone(),
                    [
                        "build", source.clone(), "--build-type", "Release", "-o",
                        "{out}/{name}-{label}"
                    ]
                )
            )
            _emit := try must(
                "ms emit {name}",
                capture(
                    cli.clone(),
                    [
                        "emit", source.clone(), "-o", "{out}/{name}-{label}.go"
                    ]
                )
            )

    var results = Map[String, JsonValue]()

    for name in workloads:
        var samples = Map[String, List[Float]]()
        samples.add("before", List[Float]())
        samples.add("after", List[Float]())

        // One correctness/warm-up execution per binary, excluded from measurements.
        for label in ["before", "after"]:
            try execute("{out}/{name}-{label}", cpu)

        for i in 0..runs:
            for label in (if i % 2 == 0: ["before", "after"] else: ["after", "before"]):
                start := now_ns()
                try execute("{out}/{name}-{label}", cpu)

                elapsed := (now_ns() - start).to_float() / 1000000000.0
                var list = samples.get_or(label, [])
                list.append(elapsed)
                samples.add(label.clone(), list)
                (
                    stdout().write(
                        "{name} {label} run {i + 1}: {elapsed.to_fixed(6)}s\n"
                    ).get()
                )

        before := median(samples.get_or("before", []))
        after := median(samples.get_or("after", []))
        var entry = Map[String, JsonValue]()
        var seconds = Map[String, JsonValue]()
        var medians = Map[String, JsonValue]()
        for label in ["before", "after"]:
            seconds.add(
                label.clone(), jlist(samples.get_or(label, []).map(fn s: jfloat(s)))
            )
        medians.add("before", jfloat(before))
        medians.add("after", jfloat(after))
        entry.add("seconds", jobject(seconds))
        entry.add("median_seconds", jobject(medians))
        entry.add("speedup", jfloat(before / after))
        results.add(name.clone(), jobject(entry))

    var report = Map[String, JsonValue]()
    report.add("platform", jstr(platform()))
    report.add("build_type", jstr("Release"))
    report.add("runs", jint(runs))
    report.add(
        "cpu_affinity", if cpu == "": JsonValue.Null else: jint(cpu.parse_int().get(0))
    )

    var names = Map[String, JsonValue]()
    for label in ["before", "after"]:
        names.add(label.clone(), jstr(clis.get_or(label, "")))
    report.add("clis", jobject(names))
    report.add("results", jobject(results))

    text := dump(jobject(report))
    write_text("{out}/results.json", text)
    return ok(text)

fn main() Int:
    parsed := options(
        arguments(), ["before", "after", "output", "runs", "cpu"],
        ["before", "after", "output"]
    )
    if parsed.is_error(): return fail(parsed.err().message)

    opts := parsed.get(Map[String, String]())
    runs := opts.get_or("runs", "3").parse_int().get(0)
    if runs < 1: return fail("--runs must be positive")

    return finish(run(opts, runs))
