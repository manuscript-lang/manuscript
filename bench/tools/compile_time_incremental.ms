// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write
// ms: allow_effect std.env.read
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Times rebuilds after small edits. Usage: ms run
// bench/tools/compile_time_incremental.ms [-- packages files fns] (default 40 25 10,
// about 122k lines). MS picks the compiler; SKIP_LLVM=1 skips the Release column. Each
// scenario edits the generated project, builds, and restores the file.
import (
	arguments from "@std/os/env.ms",
	remove, temporary from "@std/os/fs.ms",

	generate from "./compile_time_project.ms",
	env,
	fixed,
	ms_binary,
	must,
	now_ns,
	read_text,
	run_in,
	usage,
	write_text from "./lib.ms",
)

type Edit {
	label, file, from, to String
	// Appended to the file after the replacement.
	tail String = ""
}

fn header(p, f, k Int) String {
	return f"export fn w_{p}_{f}_{k}(x Int) Int:\n    var acc = x\n"
}

fn edits() List[Edit] {
	leaf := "src/pkg20/f10.ms"
	shared := "src/pkg0/f0.ms"
	return [
		Edit("no change", leaf.clone(), "", ""),
		Edit(
			"change a constant",
			leaf.clone(),
			header(
				20,
				10,
				0,
			) + "    for i in 0..10:\n        if i % 2 == 0:\n            acc += i * 3",
			header(
				20,
				10,
				0,
			) + "    for i in 0..10:\n        if i % 2 == 0:\n            acc += i * 5",
		),
		Edit(
			"add a statement",
			leaf.clone(),
			header(20, 10, 0),
			header(20, 10, 0) + "    acc += 1\n    acc += 2\n",
		),
		Edit(
			"add a function",
			leaf.clone(),
			header(20, 10, 0),
			header(20, 10, 0) + "    acc += extra_fn(acc)\n",
			"\nexport fn extra_fn(x Int) Int:\n    return x + 1\n",
		),
		Edit(
			"edit a shared module",
			shared,
			header(0, 0, 0),
			header(0, 0, 0) + "    acc += 1\n",
		),
	]
}

fn build(dir, profile, output String) Result[Float, Error] {
	start := now_ns()
	void must(
		"build",
		run_in(
			dir,
			ms_binary(),
			[
				"build",
				"ms.toml",
				"-o",
				output.clone(),
				"--build-type",
				profile.clone(),
			],
		),
	)?
	return ok((now_ns() - start).to_float() / 1000000000.0)
}

fn measure(dir, profile, output String) Result[Void, Error] {
	void remove(f"{dir}/.ms-cache", recursive: true)

	cold := build(dir, profile, output)?
	print(f"{profile} cold {fixed(cold, 2)} s")

	for e in edits() {
		path := f"{dir}/{e.file}"
		original := read_text(path)

		if e.from != "" {
			if not original.contains(
				e.from
			) { return error(Error(f"{e.label}: pattern not found in {e.file}")) }

			write_text(path, original.replace(e.from, e.to) + e.tail)
		}

		seconds := build(dir, profile, output)
		write_text(path, original)
		print(f"{profile} {e.label}: {fixed(seconds?, 2)} s")
	}

	return ok()
}

fn main() Int {
	args := arguments()
	var dims = [40, 25, 10]

	for i in 0..3 {
		if args.length() > i {
			v := args[i].parse_int() or 0
			if v < 1 { return usage("packages, files and fns must be positive integers") }

			dims[i] = v
		}
	}

	dir := temporary("incremental-").get().path()
	generate(dir, dims[0], dims[1], dims[2])

	root := f"{dir}/ms"
	out := f"{dir}/program"
	if measure(root, "Debug", out).is_error() { return 1 }

	if env("SKIP_LLVM", "") == "" {
		if measure(root, "Release", out).is_error() { return 1 }
	}
	return 0
}
