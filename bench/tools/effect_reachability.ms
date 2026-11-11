// Paired CLI effect-analysis measurements. Run from the repository root: ms run
// bench/tools/effect_reachability.ms -- OUT BASE CANDIDATE REPEATS SIZES MODES ACTION
// SIZES and MODES are comma-separated; ACTION is check, lint, build, or projects. Set
// MS_CACHE=off for build measurements. Pin the driver externally when supported.
import (
	JsonValue, parse, stringify from "@std/data/json.ms",
	arguments from "@std/os/env.ms",

	absolute,
	capture,
	dump,
	ensure_directory,
	exe,
	file_sha256,
	finish,
	invalid,
	jfloat,
	jint,
	jlist,
	jobject,
	jstr,
	median,
	now_ns,
	output_of,
	platform,
	read_text,
	write_text from "./lib.ms",
)

type Diagnostic:
	code: String
	severity: String

type Document:
	diagnostics: List[Diagnostic]

type Sample:
	label: String
	trial: Int
	wall_ns: Int

fn report(out: String, name: String) Unit!:
	rows := parse[List[Sample]](read_text("{out}/{name}-samples.json"))?
	var baseline = Map[Int, Float]()
	var candidate = Map[Int, Float]()

	for row in rows:
		if row.trial < 0: continue

		if row.label == "baseline": baseline.add(row.trial, row.wall_ns.to_float())
		else: candidate.add(row.trial, row.wall_ns.to_float())

	var before = List[Float]()
	var after = List[Float]()
	var ratios = List[Float]()
	var slower = 0

	for entry in baseline.entries():
		a := candidate.get(entry.key).get()
		before.append(entry.value / 1000000.0)
		after.append(a / 1000000.0)
		ratios.append(a / entry.value)
		if a > entry.value: slower += 1

	if ratios.is_empty(): return invalid("no measured pairs")

	result := jobject(
		{
			"case": jstr(name.clone()),
			"pairs": jint(ratios.length()),
			"baseline_median_ms": jfloat(median(before)),
			"candidate_median_ms": jfloat(median(after)),
			"paired_median_ratio": jfloat(median(ratios)),
			"slower_pairs": jint(slower)
		}
	)
	write_text("{out}/{name}-summary.json", dump(result))
	print(stringify(result).get())

fn padded(i: Int) String:
	return "{i}".pad_start(6, "0")

// A shared wide graph and the neighboring shapes that must not regress.
export fn probe(size: Int, mode: String) String:
	var lines = List[String]()

	if mode == "many" or mode == "cyclic":
		for i in 0..size:
			suffix := padded(i)

			if mode == "many":
				lines.append(
					"// ms: effect probe.e{suffix}\nfn sink_{suffix}() Int:\n    return 1\n"
				)
				lines.append("fn root_{suffix}() Int:\n    return sink_{suffix}()\n")
			else:
				lines.append(
					"// ms: effect probe.io\nfn root_{suffix}() Int:\n    return leaf_{suffix}()\n"
				)
				lines.append("fn leaf_{suffix}() Int:\n    return root_{suffix}()\n")

		result := if mode == "many": "root_000000() - 1" else: "0"
		lines.append("fn main() Int:\n    return {result}\n")
		return lines.join("\n")

	if mode == "allowed" or mode == "sparse":
		lines.append("// ms: allow_effect probe.io\n")
	if mode != "pure": lines.append("// ms: effect probe.io")
	lines.append("fn sink() Int:\n    return 1\n")

	for i in 0..size:
		suffix := padded(i)
		lines.append("fn leaf_{suffix}() Int:\n    return sink()\n")

	lines.append("fn hub() Int:")

	for i in 0..size:
		suffix := padded(i)
		lines.append("    leaf_{suffix}()")

	lines.append("    return 1\n")

	for i in 0..size:
		suffix := padded(i)
		if mode == "sparse" and i == 0: lines.append("// ms: allow_effect probe.none")

		target := if mode == "direct" or (mode == "sparse" and i == 0): "sink" else: "hub"
		lines.append("fn root_{suffix}() Int:\n    return {target}()\n")

	lines.append("fn main() Int:\n    return root_000000() - 1\n")
	return lines.join("\n")

fn expected_count(size: Int, mode: String, action: String) Int:
	if action != "lint": return 0
	if mode == "none" or mode == "direct": return 2 * size + 1
	if mode == "sparse": return 1
	if mode == "many": return size
	if mode == "cyclic": return 2 * size

	return 0

fn measure(
	out: String,
	binaries: List[String],
	repeats: Int,
	name: String,
	input: String,
	action: String,
	wanted: Int,
) Unit!:
	var samples = List[JsonValue]()
	var expected_stdout = ""
	var expected_stderr = ""
	labels := ["baseline", "candidate"]
	executable := "{out}/native-program{exe()}"

	for round in 0..(repeats + 1):
		for pass in 0..2:
			which := (round + pass) % 2
			binary := binaries[which]
			label := labels[which]
			trial := round - 1
			var command = [action.clone(), input.clone(), "--json"]
			if action == "build":
				command = [
					"build",
					input.clone(),
					"--build-type",
					"Release",
					"-o",
					executable.clone(),
				]

			started := now_ns()
			ran := capture(binary, command)
			elapsed := now_ns() - started

			if not ran.ok or ran.code != 0:
				write_text("{out}/{name}-{label}-{trial}.failed.stdout", ran.stdout)
				write_text("{out}/{name}-{label}-{trial}.failed.stderr", ran.stderr)

			if not ran.ok or ran.code != 0: return invalid(
				"{name}: {binary}: {ran.stderr}"
			)

			write_text("{out}/{name}-{label}-{trial}.stderr", ran.stderr)

			if round == 0 and pass == 0:
				expected_stdout = ran.stdout.clone()
				expected_stderr = ran.stderr.clone()
				write_text("{out}/{name}.stdout", ran.stdout)

			if ran.stdout != expected_stdout or ran.stderr != expected_stderr:
				return invalid("{name}: output mismatch at {label} trial {trial}")

			if action == "build":
				execution := capture(executable, [])
				if not execution.ok or execution.code != 0: return invalid(
					"{name}: native execution failed"
				)

				write_text(
					"{out}/{name}-{label}-{trial}.native.stdout",
					execution.stdout,
				)
				write_text(
					"{out}/{name}-{label}-{trial}.native.stderr",
					execution.stderr,
				)
				if (
					name != "hello"
					and (
						execution.stdout != ""
						or execution.stderr != ""
					)
				):
					return invalid("{name}: unexpected native output")
				if (
					name == "hello"
					and (
						execution.stdout != "Arguments: 0\n"
						or execution.stderr != ""
					)
				):
					return invalid("hello: unexpected native output")
			else:
				doc := parse[Document](ran.stdout)?
				var count = 0

				for d in doc.diagnostics:
					if d.severity == "error": return invalid("{name}: compiler error")

					if d.code == "MSL116": count += 1

				if count != wanted: return invalid(
					"{name}: effect count {count}, expected {wanted}"
				)

			samples.append(
				jobject(
					{
						"case": jstr(name.clone()),
						"label": jstr(label.clone()),
						"trial": jint(trial),
						"wall_ns": jint(elapsed),
						"max_resident_bytes": jint(
							ran.max_resident_bytes
						),
						"binary": jstr(binary.clone()),
						"command": jlist(
							command.map(
								fn s: jstr(s.clone())
							)
						),
						"exit": jint(ran.code),
						"input_sha256": jstr(file_sha256(input))
					}
				)
			)
			write_text("{out}/{name}-samples.json", stringify(samples).get())

	print("{name}: {repeats} exact-output pairs passed")
	report(out, name)?

fn run(args: List[String]) String!:
	if args.length() != 7: return invalid(
		"expected OUT BASE CANDIDATE REPEATS SIZES MODES ACTION"
	)

	out := absolute(args[0].clone())

	if args[6].starts_with("summary-"):
		action := args[6].slice(8, args[6].length()).get()
		for size in args[4].split(","):
			for mode in args[5].split(","):
				report(out, "{mode}-{size}-{action}")?
		return ok("summaries written")

	binaries := [absolute(args[1].clone()), absolute(args[2].clone())]
	repeats := args[3].parse_int().get(0)
	if repeats < 1: return invalid("repeats must be positive")

	ensure_directory(out)
	write_text(
		"{out}/metadata.json",
		dump(
			jobject(
				{
					"platform": jstr(platform()),
					"revision": jstr(
						output_of("git", ["rev-parse", "HEAD"])
					),
					"baseline_sha256": jstr(
						file_sha256(binaries[0])
					),
					"candidate_sha256": jstr(
						file_sha256(binaries[1])
					),
					"arguments": jlist(
						args.map(fn s: jstr(s.clone()))
					)
				}
			)
		),
	)

	action := args[6]

	if action == "projects":
		measure(
			out,
			binaries,
			repeats,
			"hello",
			absolute("examples/hello/ms.toml"),
			"check",
			0,
		)?
		measure(
			out,
			binaries,
			repeats,
			"e2e-driver",
			absolute("tools/conform.ms"),
			"check",
			0,
		)?
		measure(
			out,
			binaries,
			repeats,
			"programs",
			absolute("bench/perf/programs/ms/ms.toml"),
			"check",
			0,
		)?
		return ok("project controls passed")

	for size_text in args[4].split(","):
		size := size_text.parse_int().get(0)
		if size < 1: return invalid("size must be positive")

		for mode in args[5].split(","):
			if not ["none", "allowed", "pure", "direct", "sparse", "many", "cyclic"].contains(
				mode
			):
				return invalid("unknown mode {mode}")

			name := "{mode}-{size}-{action}"
			input := "{out}/{name}.ms"
			write_text(input, probe(size, mode))
			measure(
				out,
				binaries,
				repeats,
				name,
				input,
				action,
				expected_count(size, mode, action),
			)?

	return ok("effect controls passed")

fn main() Int:
	return finish(run(arguments()))
