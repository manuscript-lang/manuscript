// Process-cold production checker controls. Run after all compiler builds stop:
// ms run bench/tools/call_candidates.ms -- BEFORE AFTER OUTPUT ROUNDS
// Linux measurement host: taskset CPU 0; child peak RSS is retained.
import (
	absolute,
	ensure_directory,
	file_sha256,
	invalid,
	now_ns,
	read_text,
	write_text from "./lib.ms",
	arguments from "@std/os/env.ms",
	timed from "./call_candidates_process.ms",
)

fn source(count: Int, mode: String) String:
	header := "type Counter:\n    value: Int\n\nimpl Counter:\n    fn next() Counter: Counter(self.value + 1)\n\n"
	if mode == "native-chain":
		return (
			"export fn main() Int:\n    result := [0]"
			+ ".map(fn v: v + 1)".repeat(count).get()
			+ "\n    print(result[0])\n    return 0\n"
		)
	if mode == "source-chain":
		return (
			header
			+ "export fn main() Int:\n    result := Counter(0)"
			+ ".next()".repeat(count).get()
			+ "\n    print(result.value)\n    return 0\n"
		)

	var text = header + "export fn main() Int:\n    step0 := Counter(0)\n"
	for i in 0..count:
		text += "    step{i + 1} := step{i}.next()\n"
	return text + "    print(step{count}.value)\n    return 0\n"

fn measure(
	before: String,
	after: String,
	directory: String,
	rounds: Int,
	filter: String
) Unit!:
	ensure_directory(directory)
	ensure_directory("{directory}/inputs")

	var files = List[String]()

	for count in [0, 1, 4, 8, 10, 12, 14, 16, 18]:
		for mode in ["source-chain", "source-flat", "native-chain"]:
			file := "{directory}/inputs/{mode}-{count}.ms"
			write_text(file, source(count, mode))
			files.append(file.clone())

	for file in [
		"examples/hello/ms.toml", "tools/conform.ms", "bench/perf/stdlib/ms.toml"
	]:
		files.append(absolute(file.clone()))
	if filter != "": files = files.filter(fn file: file.ends_with("/{filter}"))
	if files.is_empty(): return invalid("no matching inputs")

	write_text(
		"{directory}/binaries.txt",
		"before {before} {file_sha256(before)}\nafter {after} {file_sha256(after)}\n"
	)

	var rows = "round\tlabel\tinput\twall_ns\tmax_resident_bytes\tinput_sha256\tuser_ns\tsystem_ns\n"
	var expected = Map[String, String]()

	for round in 0..rounds + 1:
		order := if round % 2 == 0: ["before", "after"] else: ["after", "before"]

		for i in 0..files.length():
			file := files[(i + round * 7) % files.length()]

			for label in order:
				binary := if label == "before": before else: after
				command := [
					"60", "taskset", "-c", "0", binary.clone(), "check", file.clone(),
					"--json"
				]
				started := now_ns()
				measured := try timed("timeout", command)
				ran := measured.result
				elapsed := now_ns() - started
				prefix := "{directory}/round-{round}-{label}-{i}"
				write_text("{prefix}.command", measured.command)
				write_text("{prefix}.stdout", ran.stdout)
				write_text("{prefix}.stderr", ran.stderr)
				write_text("{prefix}.status", "{ran.code}\n")
				if not ran.ok or ran.code != 0: return invalid(
					"check failed: {file}: {ran.stderr}"
				)

				if previous := expected.get(file):
					if previous != ran.stdout: return invalid(
						"checker output changed: {file}"
					)
				else:
					expected.add(file.clone(), ran.stdout.clone())

				rows += "{round}\t{label}\t{file}\t{elapsed}\t{ran.max_resident_bytes}\t{file_sha256(file)}\t{measured.user_ns}\t{measured.system_ns}\n"
				write_text("{directory}/samples.tsv", rows)
				print("{round} {label} {file} {elapsed} ns")

export fn main() Unit!:
	args := arguments()
	if args.length() < 4 or args.length() > 5:
		return invalid("expected BEFORE AFTER OUTPUT ROUNDS [FILTER]")

	try measure(
		absolute(args[0].clone()), absolute(args[1].clone()), absolute(args[2].clone()),
		args[3].parse_int().get(), if args.length() == 5: args[4].clone() else: ""
	)
