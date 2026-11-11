// Scaling gate (`make scaling-check`): generates inputs of 1k, 10k and 100k units and
// fails when work that should be linear grows faster. It compares ratios, never wall
// time: a shape fails when its time at 100k, minus the fixed start-up cost measured at
// 1k, exceeds BOUND times the same figure at 10k. Linear work gives about 10, n log n
// about 12, quadratic work about 100, so the default bound of 30 leaves room for cache
// effects and noisy runners. Compile shapes (long functions, many locals, long
// interpolation, many impls, many functions, many branches, big literals) run
// `ms check` and `ms emit`; the runtime half runs tests/scaling/containers.ms at 10k
// and 100k and compares each phase's own timing. A ratio over the bound is measured
// again (RETRIES times) and the lowest kept. An input that exceeds TIMEOUT seconds
// fails. MS names the ms to measure (default target/release/ms); SCALING_BOUND and
// SCALING_TIMEOUT override the limits. Usage: ms run tools/scaling-check.ms [--
// shape...]
import (
	stdout from "@std/io/io.ms",
	arguments, working_directory from "@std/os/env.ms",
	temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	StringBuilder from "@std/string.ms",
	monotonic, seconds from "@std/time.ms",

	env, tool_ms from "./lib.ms",
)

// Source of `shape` with `n` units.
fn generate(shape: String, n: Int) String:
	var out = StringBuilder()

	if shape == "long_function":
		out.append("export fn main() Int:\n    var t = 0\n")
		for i in 0..n: out.append("    t += {i}\n")
		out.append("    return t % 256\n")
	else if shape == "many_locals":
		out.append("export fn main() Int:\n    a0 := 0\n")
		for i in 1..n: out.append("    a{i} := a{i - 1} + 1\n")
		out.append("    return a{n - 1} % 256\n")
	else if shape == "long_interpolation":
		out.append("export fn main() Int:\n    x := 1\n    s := \"")
		for i in 0..n: out.append("\{x\}a")
		out.append("\"\n    return s.length() % 256\n")
	else if shape == "many_impls":
		for i in 0..n:
			out.append(
				"type T{i}:\n    v: Int\nimpl T{i}:\n    fn get() Int:\n        return self.v + {i}\n\n"
			)
		out.append("export fn main() Int:\n    return T0(1).get() % 256\n")
	else if shape == "many_functions":
		for i in 0..n: out.append("fn f{i}(x: Int) Int:\n    return x + {i}\n\n")
		out.append("export fn main() Int:\n    return f0(1) % 256\n")
	else if shape == "many_branches":
		out.append("export fn main() Int:\n    var t = 0\n    var x = 1\n")
		for i in 0..n: out.append(
			"    if x > {i}:\n        t += 1\n    else:\n        t += 2\n"
		)
		out.append("    return t % 256\n")
	else if shape == "big_literal":
		out.append("export fn main() Int:\n    xs := [0")
		for i in 1..n: out.append(", {i}")
		out.append("]\n    return xs.length() % 256\n")

	return out.build()

// Extra measurements of a shape whose ratio is over the bound.
RETRIES := 2
SHAPES := [
	"long_function", "many_locals", "long_interpolation", "many_impls",
	"many_functions", "many_branches", "big_literal"
]

// Seconds `ms <command> <file> [extra]` took, or -1.0 when it failed or hit the
// timeout.
fn measure(
	ms: String,
	command: String,
	file: String,
	extra: List[String],
	limit: Int,
) Float:
	var args = [command.clone(), file.clone()]
	for e in extra: args.append(e.clone())

	started := monotonic()
	ran := run(ms.clone(), args, RunOptions(timeout: seconds(limit))).wait()
	took := (monotonic().difference(started).to_nanoseconds().to_float() / 1000000000.0)
	if ran.is_error(): return -1.0
	if ran.get().exit_code != 0: return -1.0

	return took

// The growth ratio of `big` over `mid` once `base` is removed; `floor` keeps a
// sub-noise `mid` from inflating it.
fn growth(base: Float, mid: Float, big: Float, floor: Float) Float:
	var denominator = mid - base
	if denominator < floor: denominator = floor
	return (big - base) / denominator

fn say(text: String) Unit:
	stdout().write(text).get()

fn show(ratio: Float) String:
	tenths := (ratio * 10.0).truncate_to_int().get(0)
	return "{tenths / 10}.{tenths % 10}x"

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root.clone())
	bound := env("SCALING_BOUND", "30").parse_float().get(30.0)
	limit := env("SCALING_TIMEOUT", "300").parse_int().get(300)
	var shapes = List[String]()
	for a in arguments(): shapes.append(a.clone())

	compile_only := shapes.length() > 0
	if shapes.is_empty(): shapes = SHAPES.clone()

	scratch := temporary("ms-scaling-").get()
	var failures = 0
	var checked = 0

	for shape in shapes:
		var files = List[String]()

		for n in [1000, 10000, 100000]:
			file := "{scratch.path()}/{shape}_{n}.ms"
			write_file(file, generate(shape, n)).wait().get()
			files.append(file)

		for command in ["check", "emit"]:
			small := measure(ms.clone(), command.clone(), files[0].clone(), [], limit)
			mid := measure(ms.clone(), command.clone(), files[1].clone(), [], limit)
			big := measure(ms.clone(), command.clone(), files[2].clone(), [], limit)
			checked += 1

			if small < 0.0 or mid < 0.0 or big < 0.0:
				failures += 1
				say(
					"fail: {shape} {command} did not finish within {limit}s or exited nonzero; run ms {command} on the generated input\n"
				)
				continue

			var ratio = growth(small, mid, big, 0.05)

			// A wall-clock ratio just over the bound is usually runner noise (a
			// quadratic pass is near 100x): measure again, up to RETRIES times, and
			// keep the best, so only a ratio that stays high fails.
			for attempt in 0..RETRIES:
				if ratio <= bound: break

				s2 := measure(ms.clone(), command.clone(), files[0].clone(), [], limit)
				m2 := measure(ms.clone(), command.clone(), files[1].clone(), [], limit)
				b2 := measure(ms.clone(), command.clone(), files[2].clone(), [], limit)
				if s2 < 0.0 or m2 < 0.0 or b2 < 0.0: continue

				again := growth(s2, m2, b2, 0.05)
				if again < ratio: ratio = again

			say(
				"{shape} {command}: 1k {small}s 10k {mid}s 100k {big}s ratio {show(ratio)}\n"
			)

			if ratio > bound:
				failures += 1
				say(
					"fail: {shape} {command} grew {show(ratio)} from 10k to 100k (bound {bound}x); find the pass that rescans per unit and give it an index-anchored side table\n"
				)

	if not compile_only:
		program := "{root}/tests/scaling/containers.ms"
		mid := run_phases(ms.clone(), program.clone(), 10000, limit)
		big := run_phases(ms.clone(), program.clone(), 100000, limit)
		checked += 1

		if mid.is_empty() or big.is_empty():
			failures += 1
			say(
				"fail: tests/scaling/containers.ms did not run; run it with ms run --build-type Debug\n"
			)

		for entry in mid.entries():
			name := entry.key.clone()
			if not big.contains(name.clone()): continue

			ratio := growth(
				0.0,
				mid[name.clone()].to_float(),
				big[name.clone()].to_float(),
				1000000.0,
			)
			say(
				"{name}: 10k {mid[name.clone()] / 1000}us 100k {big[name.clone()] / 1000}us ratio {show(ratio)}\n"
			)
			checked += 1

			if ratio > bound:
				failures += 1
				say(
					"fail: {name} grew {show(ratio)} from 10k to 100k (bound {bound}x)\n"
				)

	say("checked {checked} measurements, {failures} failing\n")
	if checked == 0: return 1
	if failures > 0: return 1

	return 0

// Phase name to nanoseconds from one run of the container program at size `n`; empty
// when it failed.
fn run_phases(ms: String, program: String, n: Int, limit: Int) Map[String, Int]:
	var phases = Map[String, Int]()
	ran := run(
		ms.clone(),
		["run", program.clone(), "--build-type", "Debug", "--", "{n}"],
		RunOptions(timeout: seconds(limit * 4)),
	).wait()
	if ran.is_error(): return phases
	if ran.get().exit_code != 0: return phases

	for line in ran.get().stdout.decode_utf8().get("").split("\n"):
		parts := line.split(" ")
		if parts.length() != 2: continue

		phases[parts[0].clone()] = parts[1].parse_int().get(0)

	return phases
