// Release build time, LLVM IR size and kernel times of the LLVM backend against the
// Cranelift backend. Usage: ms run tools/llvm-direct-check.ms -- report [program...]
//
//   report   for each program (a `.ms` file or `ms.toml`; default: the YAML program and the
//            bench/perf kernels), a markdown table of release build time under both backends,
//            the LLVM IR lines, the share of functions emitted directly, and for the `bench/perf`
//            kernels the time of each kernel. Output must match; the exit status is 1 when it
//            does not. One more LLVM build runs with MS_LLVM_VERIFY=1 (untimed). GATE=1 also
//            fails when a kernel is more than 15% slower. Output equality over the whole corpus
//            is `make drift-check`.
//
// Hosts that build releases with Cranelift (Windows) have one backend, so both sides
// are identical there and the check still runs. MS picks the compiler (default
// target/debug/ms), RUNS the kernel repeats (default 5, interleaved; the minimum is
// reported).
import (
	arguments from "@std/os/env.ms",
	access,
	canonicalize,
	create_directory,
	read_file,
	remove,
	temporary_directory from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	monotonic from "@std/time.ms",

	env, exe, note, run_program from "./lib.ms",
)

fn ms_path() String:
	return env("MS", "target/debug/ms{exe()}")

// One release build: what it took, what it emitted and what the program printed.
type Built:
	seconds: Float
	lines: Int
	functions: Int
	direct: Int
	exe: String

// The verifier runs only in its own build: it slows `opt`, and the timed builds must
// not carry it.
fn build_env(cranelift: Bool, verify: Bool) Map[String, String]:
	var vars = Map[String, String]()
	vars.add("MS_KEEP_LL", "1")
	if cranelift: vars.add("MS_BACKEND", "cranelift")
	if verify: vars.add("MS_LLVM_VERIFY", "1")
	return vars

// The text of `ms-keep.ll`, then `ms-keep-1.ll`, ... in `dir`.
fn kept_ir(dir: String) String:
	var text = ""
	var part = 0

	while part < 256:
		name := if part == 0: "ms-keep.ll" else: "ms-keep-{part}.ll"
		path := "{dir}/{name}"

		if access(path, 0).is_error():
			if part > 0: break
		else:
			text += read_file(path).wait().get().decode_utf8().get("")

		part += 1

	return text

// Functions in `ir` and how many hold a value the direct emitter named (`%vN`). A
// function with no value is not counted, so the share is a lower bound.
fn count_functions(ir: String) List[Int]:
	var functions = 0
	var direct = 0
	var in_direct = false

	for line in ir.split("\n"):
		if line.starts_with("define "):
			functions += 1
			in_direct = false
		else if (
			not in_direct
			and line.trim_start().starts_with("%v")
			and line.contains(" = ")
		):
			in_direct = true
			direct += 1

	return [functions, direct]

fn build(source: String, dir: String, cranelift: Bool, verify: Bool) Built!:
	ms := absolute_ms()?
	path := canonicalize(source)?
	started := monotonic()
	ran := run(
		ms,
		["build", path, "-o", "{dir}/prog{exe()}"],
		RunOptions(cwd: dir.clone(), env: build_env(cranelift, verify)),
	).wait()?
	seconds := monotonic().difference(started).to_nanoseconds().to_float() / 1.0e9
	if ran.exit_code != 0:
		return error(
			Error(
				"ms build {source} failed:\n{ran.stderr.decode_utf8().get("")}"
			)
		)

	ir := kept_ir(dir)
	counts := count_functions(ir)
	return ok(
		Built(
			seconds,
			ir.split("\n").length(),
			counts[0],
			counts[1],
			"{dir}/prog{exe()}",
		)
	)

fn absolute_ms() String!:
	return canonicalize(ms_path())

// Standard output of one run.
fn output(exe_path: String) String!:
	ran := run(exe_path, [], RunOptions()).wait()?
	if ran.exit_code != 0:
		return error(
			Error(
				"{exe_path} exited {ran.exit_code}: {ran.stderr.decode_utf8().get("")}"
			)
		)

	return ok(ran.stdout.decode_utf8().get(""))

// `name micros checksum` lines of a kernel program as `name checksum` and the times.
fn parse_kernels(text: String) List[List[String]]:
	var rows = List[List[String]]()

	for line in text.split("\n"):
		parts := line.split(" ")
		if parts.length() == 3: rows.append(
			[parts[0].clone(), parts[1].clone(), parts[2].clone()]
		)

	return rows

fn checksums(rows: List[List[String]]) String:
	return rows.map(fn r: "{r[0]} {r[2]}").join("\n")

fn row(name: String, old: Built, new: Built) String:
	share := if new.functions == 0: 0.0 else: new.direct.to_float() * 100.0 / new.functions.to_float()
	return "| {name} | {old.seconds.to_fixed(2)} s | {new.seconds.to_fixed(2)} s | {new.lines} | {new.direct} of {new.functions} ({share.to_fixed(1)}%) |"

fn runs_wanted() Int:
	return env("RUNS", "5").parse_int().get(5)

fn keep_min(var best: Map[String, Int], name: String, micros: Int) Unit:
	if not best.contains(name) or micros < best.get(name).get(micros):
		best.add(name, micros)

// Smallest time of each kernel over `runs` interleaved runs of both builds, in input
// order.
fn kernel_times(old: String, new: String, runs: Int) List[List[String]]!:
	var names = List[String]()
	var best_old = Map[String, Int]()
	var best_new = Map[String, Int]()

	for n in 0..runs:
		old_rows := parse_kernels(output(old)?)
		new_rows := parse_kernels(output(new)?)
		if n == 0: names = old_rows.map(fn r: r[0].clone())
		for r in old_rows:
			keep_min(var best_old, r[0].clone(), r[1].parse_int().get(0))
		for r in new_rows:
			keep_min(var best_new, r[0].clone(), r[1].parse_int().get(0))

	return ok(
		names.map(
			fn k: [
				k.clone(),
				"{best_old.get(k).get(0)}",
				"{best_new.get(k).get(0)}",
			]
		)
	)

// Builds `source` with both backends and appends its table row; `false` when the two
// programs print different results.
fn report_program(
	source: String,
	kernels: Bool,
	var lines: List[String],
	var slow: List[String],
) Bool!:
	root := temporary_directory("ms-llvm-direct-")?
	create_directory("{root}/old")?
	create_directory("{root}/new")?
	create_directory("{root}/verify")?

	old := build(source, "{root}/old", true, false)?
	new := build(source, "{root}/new", false, false)?

	// Fails the program when LLVM's verifier rejects any pass's output.
	_verified := build(source, "{root}/verify", false, true)?
	lines.append(row(source, old, new))

	var same = true

	if kernels:
		old_rows := parse_kernels(output(old.exe)?)
		new_rows := parse_kernels(output(new.exe)?)
		same = checksums(old_rows) == checksums(new_rows)

		for k in kernel_times(old.exe, new.exe, runs_wanted())?:
			o := k[1].parse_int().get(0)
			n := k[2].parse_int().get(0)
			ratio := if o == 0: 1.0 else: n.to_float() / o.to_float()
			mark := if ratio > 1.15: " **slower**" else: ""
			if ratio > 1.15: slow.append("{source} {k[0]}")
			note("  {k[0]}: {o} us -> {n} us ({ratio.to_fixed(2)}x){mark}")
	else:
		same = output(old.exe)? == output(new.exe)?

	remove(root, recursive: true)?
	return ok(same)

fn report(programs: List[String]) Int:
	var lines = [
		"| program | build (Cranelift) | build (LLVM) | IR lines (LLVM) | functions emitted directly |",
		"| --- | ---: | ---: | ---: | --- |"
	]
	var slow = List[String]()
	var failed = false

	for source in programs:
		kernels := source.contains("bench/perf")
		result := report_program(source, kernels, var lines, var slow)

		if result.is_error():
			note("{source}: {result.error().map(fn e: e.message).get("failed")}")
			failed = true
		else if not result.get(true):
			note("{source}: the output differs between the LLVM and Cranelift builds")
			failed = true

	print(lines.join("\n"))
	if failed: return 1
	if env("GATE", "") != "" and not slow.is_empty(): return 1

	return 0

fn main() Int:
	args := arguments()

	if args.is_empty():
		note("usage: ms run tools/llvm-direct-check.ms -- report [program...]")
		return 2

	if args[0] != "report":
		note("unknown mode {args[0]}")
		return 2

	var programs = args.slice(1, args.length()).get(List[String]())
	if programs.is_empty():
		programs = [
			"tools/llvm-direct/yaml.ms", "bench/perf/kernels/ms/ms.toml",
			"bench/perf/competence/ms/ms.toml"
		]
	return report(programs)
