// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write
// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.process.read
// ms: allow_effect std.system.read

import (
	stdout from "@std/io/io.ms",
	max, min, sqrt from "@std/math/math.ms",
	environment from "@std/os/env.ms",
	cpu_usage from "@std/os/process.ms",
	runtime_counts from "@std/os/system.ms",
	fail from "@std/test/test.ms",
	monotonic from "@std/time.ms",
)

/*
Measurement driver for `bench` blocks. `ms bench` runs each block in its own process. The block's body is one
iteration; this module repeats it, times it and reports per-iteration statistics. The entry that `ms bench` builds
calls `run_bench_block` with the block's body, so programs do not call it themselves.
The whole body is timed, and its last value, when it has one, is kept so the work that computed it stays in the program.

Settings come from environment variables that `ms bench` fills from its flags: `MS_BENCH_TIME_MS` (target time per
sample, default 100), `MS_BENCH_SAMPLES` (default 10) and `MS_BENCH_ITERATIONS` (a fixed iteration count; 0
calibrates). A block written `bench "name" per N:` performs N operations per iteration, and every statistic is per
operation.

The result is one line on standard output: `MSBENCH ` followed by a JSON object. It holds the time in nanoseconds per operation
(one operation per iteration by default) and the process CPU time per operation (`cpu_ns`, user plus kernel,
which ignores time spent waiting for a CPU). It also holds the runtime's work counters per operation (allocations,
bytes allocated, list copies and string clones, with their bytes), taken from one extra counted run.
*/
type Settings {
	// Target duration of one sample in nanoseconds; calibration grows the iteration
	// count until a sample takes this long.
	target_nanoseconds Int
	// Timed samples to take.
	samples Int
	// Fixed iterations per sample; 0 calibrates from the target duration.
	iterations Int
}

// Calibration never runs more iterations than this per sample.
max_iterations := 100000000

/*
Runs `work` repeatedly and writes the statistics line, per operation, where each run performs `operations` operations (at least 1).
*/
fn measure[F](operations Int, work fn(var F) Void!, var state F) Void! {
	if operations < 1 { return fail("measure: operations must be at least 1") }

	body := work
	config := settings()
	var count = max(config.iterations, 1)

	if config.iterations == 0 {
		// Calibration doubles as the warmup.
		while true {
			elapsed := time_batch(body, state, count)?
			if elapsed >= config.target_nanoseconds or count >= max_iterations { break }

			count = next_count(count, elapsed, config.target_nanoseconds)
		}
	}

	var times = List[Float](reserve: config.samples)
	cpu_before := cpu_usage()?

	for unused in 0..config.samples {
		elapsed := time_batch(body, state, count)?
		times.append(elapsed.to_float() / (count * operations).to_float())
	}

	cpu_after := cpu_usage()?
	cpu_micros := (
		cpu_after.user_microseconds
		+ cpu_after.system_microseconds
		- cpu_before.user_microseconds
		- cpu_before.system_microseconds
	)
	cpu_ns := (
		cpu_micros.to_float()
		* 1000.0
		/ (count * config.samples * operations).to_float()
	)
	sorted := times.sorted(
		(a, b) => (if a < b { - 1 } else { (if a > b { 1 } else { 0 }) })
	)
	n := sorted.length().to_float()
	mean := sorted.fold(0.0, (total, t) => total + t) / n
	deviations := sorted.map(t => (t - mean) * (t - mean))
	variance := deviations.fold(0.0, (total, d) => total + d) / n
	last := sorted.length() - 1
	median := (sorted[last / 2] + sorted[(last + 1) / 2]) / 2.0

	// One more run, counted: the runtime's work counters do not depend on machine load,
	// so the per-operation figures are exact and a change in them is a change in the
	// work done.
	before := runtime_counts()?
	body(state)?

	after := runtime_counts()?
	ops := operations.to_float()
	allocations := (after.allocations - before.allocations).to_float() / ops
	allocated := (after.allocated_bytes - before.allocated_bytes).to_float() / ops
	list_copies := (after.list_copies - before.list_copies).to_float() / ops
	list_copied := (after.list_copy_bytes - before.list_copy_bytes).to_float() / ops
	string_clones := (after.string_clones - before.string_clones).to_float() / ops
	string_cloned := (
		(after.string_clone_bytes - before.string_clone_bytes).to_float()
		/ ops
	)
	mir_ops := (after.operations - before.operations).to_float() / ops
	line := f"MSBENCH \{\"iterations\":{count},\"operations\":{operations},\"samples\":{config.samples},\"min_ns\":{sorted[0]},\"median_ns\":{median},\"mean_ns\":{mean},\"max_ns\":{sorted[last]},\"stddev_ns\":{sqrt(variance)},\"cpu_ns\":{cpu_ns},\"allocations\":{allocations},\"allocated_bytes\":{allocated},\"list_copies\":{list_copies},\"list_copy_bytes\":{list_copied},\"string_clones\":{string_clones},\"string_clone_bytes\":{string_cloned},\"mir_ops\":{mir_ops}\}\n"
	stdout().write(line).get()
}

// Called by the entry that `ms bench` builds, with each block's body; programs do not
// call it. The body is one iteration to repeat and time.
export fn run_bench_block(body fn() Void!, operations Int) Void! {
	var null = 0
	return measure(operations, (var unused) => body(), null)
}

// Called by the entry that `ms bench` builds for a file with a `make_fixture`, with
// each block's body, which takes the file's fixture; programs do not call it. The
// fixture is made, and `before_all` and `before_each` have run, before the timing
// starts, and `after_each` and `after_all` run after it.
export fn run_bench_fixture[F](
	body fn(var F) Void!,
	operations Int,
	var state F
) Void! {
	return measure(operations, body, state)
}

fn settings() Settings {
	environment := environment().get_or(Map[String, String]())
	var found = Settings(100 * 1000000, 10, 0)
	text := environment.get("MS_BENCH_TIME_MS")
	if text != null {
		found.target_nanoseconds = max(text.parse_int() or 100, 1) * 1000000
	}

	text := environment.get("MS_BENCH_SAMPLES")
	if text != null {
		found.samples = max(text.parse_int() or 10, 1)
	}

	text := environment.get("MS_BENCH_ITERATIONS")
	if text != null {
		found.iterations = max(text.parse_int() or 0, 0)
	}
	return found
}

// Internal: runs `body` `count` times and returns the elapsed nanoseconds. The first
// failure stops the run and is returned.
fn time_batch[F](body fn(var F) Void!, var state F, count Int) Int! {
	started := monotonic()
	for unused in 0..count {
		body(state)?
	}
	return ok(monotonic().difference(started).to_nanoseconds())
}

// Internal: returns the iteration count whose sample should take about `target`
// nanoseconds, given that `count` took `elapsed`.
fn next_count(count Int, elapsed Int, target Int) Int {
	scaled := count * target / max(elapsed, 1) * 12 / 10
	return min(max(scaled, count + 1), min(count * 100, max_iterations))
}
