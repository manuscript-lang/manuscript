# Eight CPU-bound jobs (fib(38)) spread over 1, 2 and 4 workers; best wall time of N runs in ms (bench/perf/workers).
# Usage: ms run bench/tools/workers.ms [-- repeats]; MS picks the compiler.
import (
    capture,
    finish,
    left,
    must,
    ms_binary,
    now_ns,
    repeats,
    right,
    usage
) from "./lib.ms"
import temporary from "@std/os/fs.ms"
import arguments from "@std/os/process.ms"

fn run(work: String, n: Int) Result[String, Error]:
    let app = "{work}/app"
    let _built = try must(
        "ms build",
        capture(
            ms_binary(), ["build", "bench/perf/workers/ms.toml", "-o", app.clone()]
        )
    )
    var rows = [
        left("workers", 8) + " " + right("best ms", 10) + " " + right(
            "speedup", 8
        )
    ]
    var one = 0
    var last = ""

    for k in [1, 2, 4]:
        var best = 999999999

        for _i in 0..n:
            let start = now_ns()
            last = try must("workers {k}", capture(app, ["{k}", "8", "38"]))

            let ms = (now_ns() - start) / 1000000
            if ms < best: best = ms

        if one == 0: one = best
        rows.append(
            left("{k}", 8) + " " + right("{best}", 10) + " " + right(
                (one.to_float() / best.to_float()).to_fixed(2) + "x", 8
            )
        )

    rows.append(last.trim_end())
    return ok(rows.join("\n"))

export fn main() Int:
    var n = 3
    let args = arguments()

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return usage("repeats must be a positive integer")

    let tmp = temporary("workers-").get()
    return finish(run(tmp.path(), n))
