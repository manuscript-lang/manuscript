// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write
// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Generates the same program in Manuscript, Go and Rust and times each build. Usage: ms
// run bench/perf/tools/compile_time.ms [-- packages files fns] (default 40 25 10, about
// 122k lines of Manuscript) OUT keeps the generated sources; MS picks the compiler;
// SKIP_LLVM=1 skips the release build; SKIP_RUST=1 skips the Rust builds (CARGO picks
// cargo). Generated Manuscript and Go source contains many braces; `q` writes them as ‹
// and › so the generator reads as source.
import (
	arguments, set_environment from "@std/os/env.ms",
	remove, temporary from "@std/os/fs.ms",

	generate from "./compile_time_project.ms",
	absolute,
	env,
	fail,
	ms_binary,
	must,
	now_ns,
	run_in,
	usage,
	write_text from "./lib.ms",
)

fn timed(label, dir, program String, args List[String]) Result[Void, Error] {
	start := now_ns()
	void must(label, run_in(dir, program, args))?

	seconds := (now_ns() - start).to_float() / 1000000000.0
	print(f"{label} {seconds.to_fixed(2)} s")
	return ok()
}

fn drop_cache(dir String) Void {
	void remove(f"{dir}/.ms-cache", recursive: true)
}

fn run(out String, p, f, k Int) Result[Void, Error] {
	generate(out, p, f, k)

	ms := ms_binary()
	go := env("GO", "go")
	void must("go clean", run_in(f"{out}/go", go, ["clean", "-cache"]))?
	timed("go cold:  ", f"{out}/go", go, ["build", "-o", "../gobin", "."])?
	timed("ms check: ", f"{out}/ms", ms, ["check", "--only", "types", "ms.toml"])?
	timed(
		"ms build --emit mir:  ",
		f"{out}/ms",
		ms,
		["build", "--emit", "mir", "ms.toml"],
	)?
	drop_cache(f"{out}/ms")
	timed(
		"ms debug: ",
		f"{out}/ms",
		ms,
		["build", "ms.toml", "-o", "../msbin_d", "--build-type", "Debug"],
	)?
	drop_cache(f"{out}/ms")
	set_environment("MS_BACKEND", "cranelift").get()
	timed("ms clif:  ", f"{out}/ms", ms, ["build", "ms.toml", "-o", "../msbin_c"])?
	set_environment("MS_BACKEND", null).get()

	if env("SKIP_LLVM", "") == "" {
		drop_cache(f"{out}/ms")
		timed("ms release:", f"{out}/ms", ms, ["build", "ms.toml", "-o", "../msbin"])?
	}

	if env("SKIP_RUST", "") == "" {
		cargo := env("CARGO", "cargo")
		rust_timed("rust check:  ", out, cargo, ["check"])?
		rust_timed("rust debug:  ", out, cargo, ["build"])?
		rust_timed("rust release:", out, cargo, ["build", "--release"])?
	}
}

// Times one cargo build from a cold target directory.
fn rust_timed(label, out, cargo String, args List[String]) Result[Void, Error] {
	void remove(f"{out}/rs/target", recursive: true)
	return timed(label, f"{out}/rs", cargo, args)
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

	keep := env("OUT", "")
	var out = ""

	if keep != "" {
		out = absolute(keep)
		void remove(out, recursive: true)
	} else {
		out = temporary("compile-time-").get().path()
	}

	result := run(out, dims[0], dims[1], dims[2])
	if result.is_error() { return fail(result.err().message) }

	return 0
}
