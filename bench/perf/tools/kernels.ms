// ms: allow_effect std.env.read
// ms: allow_effect std.env.write
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Whole-kernel comparisons against hand-written Go, Rust and (kernels only) C, minimum
// of N runs (bench/perf/kernels, bench/perf/competence). Usage: ms run
// bench/perf/tools/kernels.ms -- <kernels|competence> [repeats]
// kernels: c-ms is the C a no-GC Manuscript backend would emit; ABLATE=1 adds c-ms builds with one runtime check removed each.
// MS, GO, RUSTC and CC pick the tools.
import (
	arguments from "@std/os/env.ms",
	CopyOptions, copy, create_directory, temporary from "@std/os/fs.ms",

	ablations, base_versions, c_versions, summarize from "./kernels_table.ms",
	build_go,
	build_ms,
	build_rust,
	capture,
	env,
	fail,
	finish,
	must,
	repeats from "./lib.ms",
	run_trials from "./trials.ms",
)

fn build_c(source, out String, flags List[String]) Result[Void, Error] {
	var args = ["-O2", "-std=c11", "-ffp-contract=off"].concat(flags)
	args = args.concat([source.clone(), "-o", out.clone()])
	void must(f"cc {source}", capture(env("CC", "cc"), args))?
}

fn run(suite String, n Int, work String) Result[String, Error] {
	here := f"bench/perf/{suite}"
	for dir in ["go", "ms", "rust"] {
		copy(
			f"{here}/{dir}",
			f"{work}/{dir}",
			CopyOptions(recursive: true, replace: true),
		)?
	}
	for dir in ["rust-checked", "c", "c-ms"] {
		create_directory(f"{work}/{dir}")?
	}
	build_go(f"{work}/go", f"{work}/go/bench")?
	build_rust(f"{work}/rust/main.rs", f"{work}/rust/bench", [])?
	build_rust(
		f"{work}/rust/main.rs",
		f"{work}/rust-checked/bench",
		["-C", "overflow-checks=on"],
	)?
	build_ms(f"{work}/ms", f"{work}/ms/bench")?

	var versions = base_versions()

	if suite == "kernels" {
		build_c(f"{here}/c/plain.c", f"{work}/c/bench", [])?
		build_c(f"{here}/c/ms.c", f"{work}/c-ms/bench", [])?
		versions = versions.concat(c_versions())

		if env("ABLATE", "0") == "1" {
			flags := [
				["c-ms-no-poll", "-DMS_NO_POLL"],
				["c-ms-no-overflow", "-DMS_NO_OVERFLOW"],
				["c-ms-no-bounds", "-DMS_NO_BOUNDS"],
				[
					"c-ms-unchecked", "-DMS_NO_POLL -DMS_NO_OVERFLOW -DMS_NO_BOUNDS"
				],
			]

			for entry in flags {
				create_directory(f"{work}/{entry[0]}")?
				build_c(
					f"{here}/c/ms.c",
					f"{work}/{entry[0]}/bench",
					entry[1].split(" "),
				)?
			}

			versions = versions.concat(ablations())
		}
	}

	raw := run_trials(versions, v => f"{work}/{v}/bench", n)?
	return summarize(raw, suite, n, versions)
}

fn main() Int {
	args := arguments()
	if args.is_empty() or (args[0] != "kernels" and args[0] != "competence") {
		return fail("usage: kernels.ms -- <kernels|competence> [repeats]")
	}

	var n = 5

	if args.length() > 1 {
		if parsed := repeats(args[1]) {
			n = parsed
		} else {
			return fail("repeats must be a positive integer")
		}
	}

	tmp := temporary(f"{args[0]}-").get()
	return finish(run(args[0], n, tmp.path()))
}
