from "@std/math.ms" import sqrt
from "@std/io.ms" import stdout
from "@std/process.ms" import control
from "@std/time.ms" import clock

# Measurement driver for `bench` blocks. `ms bench` runs each block in its own process; the block's body is one iteration,
# and this module repeats it, times it, and reports per-iteration statistics. The entry that `ms bench` builds calls
# `run_bench_block` with the block's body, so programs do not call it themselves.
# Settings come from environment variables that `ms bench` fills from its flags: MS_BENCH_TIME_MS (target time per sample,
# default 100), MS_BENCH_SAMPLES (default 10), and MS_BENCH_ITERATIONS (a fixed iteration count; 0 calibrates).
# The result is one line on standard output: `MSBENCH ` followed by a JSON object of nanoseconds per iteration.
# Run settings.
type Settings:
    # Target duration of one sample in nanoseconds; calibration grows the iteration count until a sample takes this long.
    target_nanoseconds: Int
    # Timed samples to take.
    samples: Int
    # Fixed iterations per sample; 0 calibrates from the target duration.
    iterations: Int

def max(left: Int, right: Int) -> Int:
    return left if left > right else right

def min(left: Int, right: Int) -> Int:
    return left if left < right else right

# Calibration never runs more iterations than this per sample.
let max_iterations = 100000000

def settings() -> Settings:
    let environment = control().environment().get(Map[String, String]())
    var found = Settings(100 * 1000000, 10, 0)
    if let text = environment.get("MS_BENCH_TIME_MS"):
        found.target_nanoseconds = max(text.parse_int().get(100), 1) * 1000000
    if let text = environment.get("MS_BENCH_SAMPLES"):
        found.samples = max(text.parse_int().get(10), 1)
    if let text = environment.get("MS_BENCH_ITERATIONS"):
        found.iterations = max(text.parse_int().get(0), 0)
    return found

# Runs `body` `count` times and returns the elapsed nanoseconds; the first failure stops the run and is returned.
def time_batch(
    body: Callable[[], Result[Unit, Error]],
    count: Int
) -> Result[Int, Error]:
    let clk = clock()
    let started = clk.now()
    for unused in 0..count:
        try body()
    return ok(clk.now().difference(started).to_nanoseconds())

# Returns the iteration count whose sample should take about `target` nanoseconds, given that `count` took `elapsed`.
def next_count(count: Int, elapsed: Int, target: Int) -> Int:
    let scaled = count * target / max(elapsed, 1) * 12 / 10
    return min(max(scaled, count + 1), min(count * 100, max_iterations))

# Measures `body` and writes the statistics line; the parser calls this for every `bench` block.
export def run_bench_block(
    body: Callable[[], Result[Unit, Error]]
) -> Result[Unit, Error]:
    let config = settings()
    var count = max(config.iterations, 1)

    if config.iterations == 0:
        # Calibration doubles as the warmup.
        while True:
            let elapsed = try time_batch(body, count)
            if elapsed >= config.target_nanoseconds or count >= max_iterations:
                break

            count = next_count(count, elapsed, config.target_nanoseconds)

    var times = List[Float](reserve: config.samples)

    for unused in 0..config.samples:
        let elapsed = try time_batch(body, count)
        times.append(elapsed.to_float() / count.to_float())

    let sorted = times.sorted(lambda a, b: -1 if a < b else (1 if a > b else 0))
    let n = sorted.length().to_float()
    let mean = sorted.fold(0.0, lambda total, t: total + t) / n
    let deviations = sorted.map(lambda t: (t - mean) * (t - mean))
    let variance = deviations.fold(0.0, lambda total, d: total + d) / n
    let last = sorted.length() - 1
    let median = (sorted[last / 2] + sorted[(last + 1) / 2]) / 2.0
    let line = f"MSBENCH \{\"iterations\":{count},\"samples\":{config.samples},\"min_ns\":{sorted[0]},\"median_ns\":{median},\"mean_ns\":{mean},\"max_ns\":{sorted[last]},\"stddev_ns\":{sqrt(variance)}\}\n"
    stdout().write(line).get()
    return ok(())
