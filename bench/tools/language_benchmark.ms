# Builds checked native workloads (bench/language/*.ms) with two Manuscript CLIs and compares them, alternating the first runner.
# Usage: ms run bench/tools/language_benchmark.ms -- --before MS --after MS --output DIR [--runs 3] [--cpu N]
# --cpu pins every execution to one CPU through `taskset` (Linux).
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
    write_text
) from "./lib.ms"
import arguments from "@std/os/process.ms"
import JsonValue from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

fn execute(binary: String, cpu: String) Result[Unit, Error]:
    if cpu == "":
        let _ = try must(binary, capture(binary, []))
        return ok(unit)

    let _ = try must(binary, capture("taskset", ["-c", cpu.clone(), binary.clone()]))
    return ok(unit)

fn run(opts: Map[String, String], runs: Int) Result[String, Error]:
    let out = absolute(opts.get("output").get(""))
    ensure_directory(out)

    let cpu = opts.get("cpu").get("")
    var clis = Map[String, String]()
    clis.add("before", absolute(opts.get("before").get("")))
    clis.add("after", absolute(opts.get("after").get("")))

    let workloads = ["numeric", "calls", "list", "life"]

    for name in workloads:
        for label in ["before", "after"]:
            let cli = clis.get(label).get("")
            let source = "bench/language/{name}.ms"
            let _bin = try must(
                "ms build {name}",
                capture(
                    cli.clone(),
                    [
                        "build", source.clone(), "--build-type", "Release", "-o",
                        "{out}/{name}-{label}"
                    ]
                )
            )
            let _emit = try must(
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

        # One correctness/warm-up execution per binary, excluded from measurements.
        for label in ["before", "after"]:
            try execute("{out}/{name}-{label}", cpu)

        for i in 0..runs:
            for label in (if i % 2 == 0: ["before", "after"] else: ["after", "before"]):
                let start = now_ns()
                try execute("{out}/{name}-{label}", cpu)

                let elapsed = (now_ns() - start).to_float() / 1000000000.0
                var list = samples.get(label).get([])
                list.append(elapsed)
                samples.add(label.clone(), list)
                (
                    stdout().write(
                        "{name} {label} run {i + 1}: {elapsed.to_fixed(6)}s\n"
                    ).get()
                )

        let before = median(samples.get("before").get([]))
        let after = median(samples.get("after").get([]))
        var entry = Map[String, JsonValue]()
        var seconds = Map[String, JsonValue]()
        var medians = Map[String, JsonValue]()
        for label in ["before", "after"]:
            seconds.add(
                label.clone(), jlist(samples.get(label).get([]).map(fn s: jfloat(s)))
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
        names.add(label.clone(), jstr(clis.get(label).get("")))
    report.add("clis", jobject(names))
    report.add("results", jobject(results))

    let text = dump(jobject(report))
    write_text("{out}/results.json", text)
    return ok(text)

export fn main() Int:
    let parsed = options(
        arguments(), ["before", "after", "output", "runs", "cpu"],
        ["before", "after", "output"]
    )
    if parsed.is_error(): return fail(parsed.err().message())

    let opts = parsed.get(Map[String, String]())
    let runs = opts.get("runs").get("3").parse_int().get(0)
    if runs < 1: return fail("--runs must be positive")

    return finish(run(opts, runs))
