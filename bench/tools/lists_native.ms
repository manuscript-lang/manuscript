# Builds Release Manuscript reproductions of the List workloads (bench/lists/program.ms) and measures native wall time and peak RSS.
# Usage: ms run bench/tools/lists_native.ms -- --cli MS --output DIR [--runs 3] [--cpu N]
# --cpu pins executions with `taskset` (Linux).
import (
    absolute,
    dump,
    ensure_directory,
    fail,
    file_sha256,
    finish,
    jfloat,
    jint,
    jlist,
    jobject,
    jstr,
    median,
    must,
    capture,
    now_ns,
    options,
    peak_run,
    read_text,
    write_text
) from "./lib.ms"
import arguments from "@std/os/process.ms"
import JsonValue from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

type Workload:
    name: String
    n: Int

fn body(w: Workload) String:
    let last = (w.n - 1) * 7919 % 100003
    var text = "export fn main() Int:\n    let values = build({w.n})\n    if values.length() != {w.n}: return 1\n    if values.first().get() != 0: return 2\n    if values.last().get() != {last}: return 3\n"
    if w.name == "sort":
        text += "    let result = sorted(values)\n    if result.length() != {w.n}: return 4\n    if result.first().get() != 0: return 5\n    if result.last().get() != 100002: return 6\n    if values.last().get() != {last}: return 7\n"
    return text + "    return 0\n"

fn run(opts: Map[String, String], runs: Int) Result[String, Error]:
    let out = absolute(opts.get("output").get(""))
    ensure_directory(out)

    let cli = absolute(opts.get("cli").get(""))
    let cpu = opts.get("cpu").get("")
    let source = read_text("bench/lists/program.ms")
    var results = List[JsonValue]()

    for w in [
        Workload("append", 1000000), Workload("append", 4000000),
        Workload("sort", 200000)
    ]:
        let label = "{w.name}-{w.n}"
        let program = "{out}/{label}.ms"
        write_text(program, source.replace("export fn main() Int: return 0\n", body(w)))

        let binary = "{out}/{label}"
        let _build = try must(
            "ms build",
            capture(
                cli.clone(),
                [
                    "build", program.clone(), "--build-type", "Release", "-o",
                    binary.clone()
                ]
            )
        )
        let _emit = try must(
            "ms emit",
            capture(
                cli.clone(), ["emit", program.clone(), "-o", "{out}/{label}.mir"]
            )
        )
        let _warm = try must(label, capture(binary.clone(), []))
        var seconds = List[Float]()
        var peaks = List[Float]()
        var samples = List[JsonValue]()

        for i in 0..runs:
            let start = now_ns()

            let measured = if cpu == "": try peak_run(binary.clone(), []) else: try peak_run(
                "taskset", ["-c", cpu.clone(), binary.clone()]
            )

            let elapsed = (now_ns() - start).to_float() / 1000000000.0
            seconds.append(elapsed)
            peaks.append(measured.kib.to_float())

            var sample = Map[String, JsonValue]()
            sample.add("seconds", jfloat(elapsed))
            sample.add("peak_rss_kib", jint(measured.kib))
            samples.append(jobject(sample))
            stdout().write("{label} {elapsed.to_fixed(6)}s {measured.kib} KiB\n").get()

        var result = Map[String, JsonValue]()
        result.add("name", jstr(w.name.clone()))
        result.add("elements", jint(w.n))
        result.add("samples", jlist(samples))
        result.add("median_seconds", jfloat(median(seconds)))
        result.add("median_peak_rss_kib", jfloat(median(peaks)))
        result.add("binary_sha256", jstr(file_sha256(binary.clone())))
        results.append(jobject(result))

    var report = Map[String, JsonValue]()
    report.add("cli", jstr(cli.clone()))
    report.add("cli_sha256", jstr(file_sha256(cli.clone())))
    report.add("build_type", jstr("Release"))
    report.add("results", jlist(results))

    let text = dump(jobject(report))
    write_text("{out}/results.json", text)
    return ok(text)

export fn main() Int:
    let parsed = options(
        arguments(), ["cli", "output", "runs", "cpu"], ["cli", "output"]
    )
    if parsed.is_error(): return fail(parsed.err().message())

    let opts = parsed.get(Map[String, String]())
    let runs = opts.get("runs").get("3").parse_int().get(0)
    if runs < 1: return fail("runs must be positive")

    return finish(run(opts, runs))
