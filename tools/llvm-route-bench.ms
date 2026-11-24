// Compile time of the in-process LLVM route (MS_LLVM names the shared library) against
// the opt and llc subprocess route (MS_OPT and MS_LLC name the tools), on the programs
// below, in Debug and Release. Builds alternate between the routes so drift on a shared
// runner hits both; the median and the minimum of RUNS builds (default 5) are printed
// per program, build type and route, with each executable run and its exit status and
// output compared: the routes name the module differently, so the bytes of the two
// executables differ. MS names the compiler (default .artifacts/build/ci/src/cli/ms),
// MS_LLVM the library, and MS_OPT and MS_LLC the tools of the same LLVM release. Usage:
// ms run tools/llvm-route-bench.ms
import (
	canonicalize, remove, temporary_directory from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	monotonic from "@std/time.ms",

	env, exe, note from "./lib.ms",
)

// One build: seconds, and the exit status and standard output of running the
// executable.
type Built:
	seconds Float
	behavior String

fn route_env(inproc Bool) Map[String, String]:
	var vars = Map[String, String]()

	if inproc:
		vars.add("MS_LLVM", env("MS_LLVM", ""))
	else:
		vars.add("MS_LLVM", "none")

	return vars

fn build(ms String, source String, level String, dir String, inproc Bool) Built!:
	path := canonicalize(source)?
	output := f"{dir}/prog{exe()}"
	started := monotonic()
	ran := run(
		ms,
		["build", path, "-o", output.clone(), "--build-type", level.clone()],
		RunOptions(cwd: dir.clone(), env: route_env(inproc)),
	).wait()?
	seconds := monotonic().difference(started).to_nanoseconds().to_float() / 1.0e9
	if ran.exit_code != 0:
		return error(
			Error(
				f"ms build {source} failed:\n{(ran.stderr.decode_utf8() or "")}"
			)
		)

	program := run(output.clone(), [], RunOptions(cwd: dir.clone())).wait()?
	return ok(
		Built(
			seconds,
			f"{program.exit_code}:{(program.stdout.decode_utf8() or "")}",
		)
	)

fn median(values List[Float]) Float:
	sorted := values.sorted()
	return sorted[sorted.length() / 2]

fn report(ms String, source String, level String, runs Int) Int:
	dir := temporary_directory("ms-route-bench-").get()
	var process = List[Float]()
	var inproc = List[Float]()
	var behaviors = List[String]()

	for round in 0..runs:
		for use_inproc in [false, true]:
			built := build(ms, source, level, dir.clone(), use_inproc)

			if built.is_error():
				note(f"{built.err()}")
				return 1

			if use_inproc:
				inproc.append(built.get().seconds)
			else:
				process.append(built.get().seconds)

			behaviors.append(built.get().behavior.clone())

	void remove(dir.clone(), recursive: true)

	var same = true
	for behavior in behaviors:
		if behavior != behaviors[0]: same = false

	slow := median(process)
	fast := median(inproc)
	print(
		f"| {source} | {level} | {slow.to_fixed(2)} | {fast.to_fixed(2)} | {(slow / fast).to_fixed(2)}x | {process.sorted()[0].to_fixed(2)} | {inproc.sorted()[0].to_fixed(2)} | {same} |"
	)
	if not same: return 1

	return 0

fn main() Int:
	ms := canonicalize(env("MS", f".artifacts/build/ci/src/cli/ms{exe()}")).get()
	runs := env("RUNS", "5").parse_int() or 5
	print(
		"| program | build | process median s | in-process median s | speedup | process min s | in-process min s | same behavior |"
	)
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")

	var failed = 0
	for source in ["examples/hello/src/main.ms", "tools/llvm-direct/yaml.ms"]:
		for level in ["Debug", "Release"]:
			failed += report(ms.clone(), source.clone(), level.clone(), runs)
	return if failed == 0: 0 else: 1
