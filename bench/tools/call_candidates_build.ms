// End-to-end uncached Release builds plus exact native output checks. MS_CACHE=off ms
// run bench/tools/call_candidates_build.ms -- BEFORE AFTER INPUTS OUTPUT ROUNDS
import (
	panic from "@std/core.ms",
	arguments, set_environment from "@std/os/env.ms",

	timed from "./call_candidates_process.ms",
	absolute,
	capture,
	ensure_directory,
	file_sha256,
	invalid,
	now_ns,
	write_text from "./lib.ms",
)

fn measure(
	before String,
	after String,
	inputs String,
	directory String,
	rounds Int,
	filter String,
) Void!:
	ensure_directory(directory)
	set_environment("MS_CACHE", "off")?

	var rows = "round\tlabel\tinput\twall_ns\tmax_resident_bytes\tinput_sha256\tuser_ns\tsystem_ns\n"

	for round in 0..rounds + 1:
		order := if round % 2 == 0: ["before", "after"] else: ["after", "before"]

		for count in [1, 8, 18]:
			for mode in ["source-chain", "source-flat", "native-chain"]:
				file := f"{inputs}/{mode}-{count}.ms"
				if filter != "" and not file.ends_with(f"/{filter}"): continue

				for label in order:
					binary := if label == "before": before.clone() else: after.clone()
					prefix := f"{directory}/round-{round}-{label}-{mode}-{count}"
					command := [
						"60",
						"taskset",
						"-c",
						"0",
						binary.clone(),
						"build",
						file.clone(),
						"--build-type",
						"Release",
						"-o",
						f"{directory}/program",
					]
					started := now_ns()
					measured := timed("timeout", command)?
					ran := measured.result
					elapsed := now_ns() - started
					write_text(f"{prefix}.command", "MS_CACHE=off\n" + measured.command)
					write_text(f"{prefix}.stdout", ran.stdout)
					write_text(f"{prefix}.stderr", ran.stderr)
					write_text(f"{prefix}.status", f"{ran.code}\n")
					if not ran.ok or ran.code != 0: return invalid(
						f"build failed: {file}: {ran.stderr}"
					)

					native := capture(f"{directory}/program", [])
					write_text(f"{prefix}.native.stdout", native.stdout)
					write_text(f"{prefix}.native.stderr", native.stderr)
					write_text(f"{prefix}.native.status", f"{native.code}\n")
					if (
						not native.ok
						or native.code != 0
						or native.stdout != f"{count}\n"
						or native.stderr != ""
					): return invalid(f"native output mismatch: {file}")

					rows += f"{round}\t{label}\t{file}\t{elapsed}\t{ran.max_resident_bytes}\t{file_sha256(file)}\t{measured.user_ns}\t{measured.system_ns}\n"
					write_text(f"{directory}/samples.tsv", rows)
					print(f"{round} {label} {file} {elapsed} ns")

export fn main() Void!:
	args := arguments()
	if args.length() < 5 or args.length() > 6:
		return invalid("expected BEFORE AFTER INPUTS OUTPUT ROUNDS [FILTER]")

	measure(
		absolute(args[0].clone()),
		absolute(args[1].clone()),
		absolute(args[2].clone()),
		absolute(args[3].clone()),
		args[4].parse_int() or panic("called Optional.get() on null"),
		if args.length() == 6: args[5].clone() else: "",
	)?
