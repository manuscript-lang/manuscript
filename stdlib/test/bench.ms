import max, min, sqrt from "@std/math/math.ms"
import stdout from "@std/io/io.ms"
import environment, set_environment from "@std/os/env.ms"
import fail from "@std/test/test.ms"
import monotonic from "@std/time.ms"

/*
Measurement driver for `bench` blocks. `ms bench` runs each block in its own process; the block's body is one iteration,
and this module repeats it, times it, and reports per-iteration statistics. The entry that `ms bench` builds calls
`run_bench_block` with the block's body, so programs do not call it themselves; a body may instead time its own work
with `measure`.
Settings come from environment variables that `ms bench` fills from its flags: MS_BENCH_TIME_MS (target time per sample,
default 100), MS_BENCH_SAMPLES (default 10), and MS_BENCH_ITERATIONS (a fixed iteration count; 0 calibrates).
A block written `bench "name" per N:` performs N operations per iteration, and every statistic is per operation.
The result is one line on standard output: `MSBENCH ` followed by a JSON object of nanoseconds per operation (one operation per iteration by default).
Run settings.
*/
type Settings:
    // Target duration of one sample in nanoseconds; calibration grows the iteration count until a sample takes this long.
    target_nanoseconds: Int
    // Timed samples to take.
    samples: Int
    // Fixed iterations per sample; 0 calibrates from the target duration.
    iterations: Int

// Calibration never runs more iterations than this per sample.
max_iterations := 100000000

fn settings() Settings:
    environment := environment().get(Map[String, String]())
    var found = Settings(100 * 1000000, 10, 0)
    if text := environment.get("MS_BENCH_TIME_MS"):
        found.target_nanoseconds = max(text.parse_int().get(100), 1) * 1000000
    if text := environment.get("MS_BENCH_SAMPLES"):
        found.samples = max(text.parse_int().get(10), 1)
    if text := environment.get("MS_BENCH_ITERATIONS"):
        found.iterations = max(text.parse_int().get(0), 0)
    return found

// Runs `body` `count` times and returns the elapsed nanoseconds; the first failure stops the run and is returned.
fn time_batch(body: fn() Unit!, count: Int) Int!:
    started := monotonic()
    for unused in 0..count:
        try body()
    return ok(monotonic().difference(started).to_nanoseconds())

// Returns the iteration count whose sample should take about `target` nanoseconds, given that `count` took `elapsed`.
fn next_count(count: Int, elapsed: Int, target: Int) Int:
    scaled := count * target / max(elapsed, 1) * 12 / 10
    return min(max(scaled, count + 1), min(count * 100, max_iterations))

/*
Runs `work` repeatedly and writes the statistics line, per operation for `operations` operations per run.
A bench body that needs setup outside the timed region builds its data first and then calls `measure`:
  bench "sorts":
      data := [3, 1, 2]
      try measure(1, fn: keep(data.sorted().length()))
Everything the body does before `measure` runs once, untimed.
*/
export fn measure(operations: Int, work: fn() Unit!) Unit!:
    body := work
    config := settings()
    var count = max(config.iterations, 1)

    if config.iterations == 0:
        // Calibration doubles as the warmup.
        while true:
            elapsed := try time_batch(body, count)
            if elapsed >= config.target_nanoseconds or count >= max_iterations: break

            count = next_count(count, elapsed, config.target_nanoseconds)

    var times = List[Float](reserve: config.samples)

    for unused in 0..config.samples:
        elapsed := try time_batch(body, count)
        times.append(elapsed.to_float() / (count * operations).to_float())

    sorted := times.sorted(fn a, b: (if a < b: -1 else: (if a > b: 1 else: 0)))
    n := sorted.length().to_float()
    mean := sorted.fold(0.0, fn total, t: total + t) / n
    deviations := sorted.map(fn t: (t - mean) * (t - mean))
    variance := deviations.fold(0.0, fn total, d: total + d) / n
    last := sorted.length() - 1
    median := (sorted[last / 2] + sorted[(last + 1) / 2]) / 2.0
    line := "MSBENCH \{\"iterations\":{count},\"operations\":{operations},\"samples\":{config.samples},\"min_ns\":{sorted[0]},\"median_ns\":{median},\"mean_ns\":{mean},\"max_ns\":{sorted[last]},\"stddev_ns\":{sqrt(variance)}\}\n"
    stdout().write(line).get()
    set_environment(measured_flag, "1").get()
    return ok(unit)

// Set once a body has timed its own work with `measure`.
measured_flag := "MS_BENCH_MEASURED"

// The entry `ms bench` builds calls this with each block's body; programs do not. The body runs once first (the
// warmup); a body that called `measure` has reported already, and any other body is one iteration to repeat and time.
export fn run_bench_block(body: fn() Unit!, operations: Int) Unit!:
    try body()

    environment := environment().get(Map[String, String]())
    if environment.get_or(measured_flag, "") == "1": return ok(unit)

    return measure(operations, body)

// Checks a bench's Int result so the work that computed it stays observable. Apply `try keep(value)` in the body.
// The smallest Int returns an error; choose a different checksum if that value is a valid result of your workload.
export fn keep(checksum: Int) Unit!:
    if checksum == -9223372036854775807 - 1:
        return fail(
            "bench result is the smallest Int; the workload is probably degenerate"
        )

    return ok(unit)
