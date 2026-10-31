# Plain element-wise list loops in GFLOPS (higher is better), best of N (bench/perf/listloops).
# ms is the Manuscript loops (`for i in 0..n: out[i] = ...`) built with `ms build`; c-sse2 and c-avx2 are the same loops in C at
# -O3 with strict IEEE semantics (no -ffast-math, no FMA contraction), so neither side may reorder floating-point reductions.
# Usage: ms run bench/tools/listloops.ms [-- repeats]; MS and CC pick the tools.
import build_ms, capture, env, finish, must, repeats, sample, usage from "./lib.ms"
import copy_tree, temporary from "@std/fs.ms"
import arguments from "@std/process.ms"

fn run(work: String, n: Int) Result[String, Error]:
    try copy_tree("bench/perf/listloops/ms", "{work}/ms", replace: true)
    try build_ms("{work}/ms", "{work}/ms/bench")

    let cc = env("CC", "cc")
    let source = "bench/perf/listloops/c/kernels.c"
    let _sse2 = try must(
        "cc",
        capture(
            cc,
            [
                "-O3", "-ffp-contract=off", source.clone(), "-o", "{work}/c-sse2"
            ]
        )
    )
    let _avx2 = try must(
        "cc",
        capture(
            cc,
            [
                "-O3", "-mavx2", "-ffp-contract=off", source, "-o", "{work}/c-avx2"
            ]
        )
    )
    var best = Map[String, Float]()

    for _i in 0..n:
        for v in ["ms", "c-sse2", "c-avx2"]:
            let exe = if v == "ms": "{work}/ms/bench" else: "{work}/{v}"

            for line in (try sample(exe, [])).split("\n"):
                let f = line.split(" ").filter(fn p: p != "")
                if f.length() < 2 or f[0] == "check": continue

                let key = "{f[0]} {v}"
                let value = f[1].parse_float().get(0.0)
                if value > best.get(key).get(0.0) or not best.contains(key): best.add(
                    key.clone(), value
                )

    var rows = best.keys().sorted().map(fn k: "{k} {best.get(k).get(0.0).to_fixed(2)}")
    return ok(rows.join("\n"))

export fn main() Int:
    var n = 5
    let args = arguments()

    if args.length() > 0:
        if let parsed = repeats(args[0]):
            n = parsed
        else:
            return usage("repeats must be a positive integer")

    let tmp = temporary("listloops-").get()
    return finish(run(tmp.path(), n))
