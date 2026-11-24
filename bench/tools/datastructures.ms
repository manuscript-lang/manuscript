// Core data-structure operations in Manuscript, Go and Rust (ns per operation, best of
// N) (bench/perf/datastructures). Usage: ms run bench/tools/datastructures.ms [--
// repeats]; MS picks the Manuscript compiler.
import (
	arguments from "@std/os/env.ms",
	CopyOptions, copy, temporary from "@std/os/fs.ms",

	summarize from "./datastructures_table.ms",
	build_go,
	build_ms,
	build_rust,
	finish,
	repeats,
	rotate,
	sample,
	usage from "./lib.ms",
)

fn run(work String, n Int) Result[String, Error] {
	here := "bench/perf/datastructures"
	for dir in ["go", "ms"] {
		copy(
			f"{here}/{dir}",
			f"{work}/{dir}",
			CopyOptions(recursive: true, replace: true),
		)?
	}
	build_ms(f"{work}/ms", f"{work}/ms/bench")?
	build_go(f"{work}/go", f"{work}/go/bench")?
	build_rust(f"{here}/rust/main.rs", f"{work}/rs", [])?

	var raw = List[String]()

	for i in 0..n {
		for v in rotate(["ms", "go", "rs"], i) {
			exe := if v == "rs" { f"{work}/rs" } else { f"{work}/{v}/bench" }
			for line in (sample(exe, [])?).split("\n") {
				if line != "" { raw.append(f"{v} {line}") }
			}
			raw.append(f"{v} # end")
		}
	}

	return summarize(raw, n)
}

fn main() Int {
	var n = 5
	args := arguments()

	if not args.is_empty() {
		if parsed := repeats(args[0]) {
			n = parsed
		} else {
			return usage("repeats must be a positive integer")
		}
	}

	tmp := temporary("datastructures-").get()
	return finish(run(tmp.path(), n))
}
