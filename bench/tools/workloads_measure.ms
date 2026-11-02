# Times prebuilt CLI workloads, validating every version and trial's output (bench/perf/workloads).
import Invalid, invalid, left, now_ns, right, rotate from "./lib.ms"

export type Sample:
    trial: Int
    version: String
    elapsed_ns: Int

export fn versions() List[String]:
    return ["ms", "go", "rs"]

# The samples of every trial plus the expected output (produced by the Go reference).
export type Measured:
    samples: List[Sample]
    expected: String

fn best(samples: List[Sample], version: String) Float:
    var low = 0
    for s in samples:
        if s.version == version and (low == 0 or s.elapsed_ns < low): low = s.elapsed_ns
    return low.to_float() / 1000000.0

# `run(version)` executes one program with the workload's input and returns its standard output, or an error when it fails.
export fn measure(
    repeats: Int,
    name: String,
    run: fn(String) Result[String, Invalid]
) Result[Measured, Invalid]:
    if repeats < 1: return invalid("repeats must be positive")

    # One untimed run of each version warms executable and input pages. The Go reference establishes the expected output;
    # every other output must match.
    let expected = try run("go")

    for v in ["ms", "rs"]:
        let got = try run(v)
        if got != expected: return invalid("{name}: {v} warm-up output differs from Go")

    var samples = List[Sample]()

    for trial in 0..repeats:
        for v in rotate(versions(), trial % versions().length()):
            let start = now_ns()
            let got = try run(v)
            let elapsed = now_ns() - start
            if elapsed <= 0: return invalid("{name}: nonpositive elapsed time")
            if got != expected: return invalid(
                "{name}: {v} trial {trial + 1} output differs from Go"
            )

            samples.append(Sample(trial, v.clone(), elapsed))

    return ok(Measured(samples, expected))

export fn row(name: String, samples: List[Sample]) String:
    let m = best(samples, "ms")
    let g = best(samples, "go")
    let r = best(samples, "rs")
    return (
        left(name, 24)
        + " "
        + right(m.to_fixed(3), 8)
        + " "
        + right(g.to_fixed(3), 8)
        + " "
        + right(r.to_fixed(3), 8)
        + " "
        + right((m / g).to_fixed(2), 7)
        + "x "
        + right((m / r).to_fixed(2), 7)
        + "x"
    )

export fn header() String:
    return (
        left("program", 24)
        + " "
        + right("ms ms", 8)
        + " "
        + right("go ms", 8)
        + " "
        + right("rust ms", 8)
        + " "
        + right("ms/go", 8)
        + " "
        + right("ms/rust", 8)
    )
