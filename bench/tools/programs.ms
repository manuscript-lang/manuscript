// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Compares Manuscript, Go and Rust on small whole programs (bench/perf/programs).
// Usage: ms run bench/tools/programs.ms [-- repeats]; MS, GO, RUSTC pick tools;
// BENCH_OUTPUT keeps binaries, input and raw samples.
import (
	arguments from "@std/os/env.ms",
	CopyOptions, copy, create_directory, temporary, write_file from "@std/os/fs.ms",

	absolute,
	build_go,
	build_ms,
	build_rust,
	env,
	fail,
	finish,
	repeats,
	sample from "./lib.ms",
	summarize from "./programs_table.ms",
)

fn orders() List[List[String]] {
	return [
		["go", "ms", "rust", "rust-checked"],
		["ms", "rust-checked", "go", "rust"],
		["rust-checked", "rust", "ms", "go"],
		["rust", "go", "rust-checked", "ms"],
	]
}

fn run(work String, n Int) Result[String, Error] {
	here := "bench/perf/programs"
	for dir in ["go", "ms", "rust"] {
		copy(
			f"{here}/{dir}",
			f"{work}/{dir}",
			CopyOptions(recursive: true, replace: true),
		)?
	}
	create_directory(f"{work}/rust-checked")?

	var input = List[String]()
	for i in 0..200000 {
		input.append(f"2026-03-01T00:00:00Z 10.1.2.3 GET /api/users/{i} 200\n")
	}

	lines := input.join("")
	write_file(f"{work}/lines.txt", lines, replace: true).wait()?
	build_go(f"{work}/go", f"{work}/go/bench")?
	build_rust(f"{work}/rust/main.rs", f"{work}/rust/bench", [])?
	build_rust(
		f"{work}/rust/main.rs",
		f"{work}/rust-checked/bench",
		["-C", "overflow-checks=on"],
	)?
	build_ms(f"{work}/ms", f"{work}/ms/bench")?

	var raw = List[String]()
	rotations := orders()

	for i in 0..n {
		for v in rotations[i % 4] {
			out := sample(f"{work}/{v}/bench", [], lines)?
			for line in out.split("\n") {
				if line != "" { raw.append(f"{v} {line}") }
			}
		}
	}

	return summarize(raw, n)
}

fn main() Int {
	var n = 7
	args := arguments()

	if not args.is_empty() {
		if parsed := repeats(args[0]) {
			n = parsed
		} else {
			return fail("repeats must be a positive integer")
		}
	}

	keep := env("BENCH_OUTPUT", "")

	if keep != "" {
		create_directory(keep, recursive: true).get()
		return finish(run(absolute(keep), n))
	}

	tmp := temporary("programs-").get()
	return finish(run(tmp.path(), n))
}
