// Copy sweep (`make copy-check`): builds the programs and test fixtures of the corpus
// with
// `MS_COPY_PROBE=1`, which makes the compiler print every copy of a value that owns memory
// (a string, list, record, closure or runtime object) that no written `.clone()` asked
// for. Such a value has one owner and a program duplicates it only through a written
// `.clone()`, which the probe leaves out, so each line is a lowering site to fix; the
// sweep fails while any remain. Arguments name the files to sweep instead. MS names the
// ms that builds the programs (default .artifacts/build/ci/src/cli/ms). Usage: ms run
// tools/copy-check.ms [-- files]
import (
	arguments, change_directory, working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// The probe lines the compiler printed on standard error, without their prefix.
fn copies(text String) List[String] {
	sites := text.split("\n").collect().filter(
		line => line.starts_with("copy-probe\t")
	).map(line => (line.slice(11, line.length()).clone()))
	return sites
}

fn main() Int {
	root := working_directory().get()
	var files = arguments().map(f => f.clone())
	if files.is_empty() {
		for dir in ["tests/lang", "tests/checks/ownership-counts"] {
			for f in glob(dir, GlobOptions(patterns: ["**/*.ms"])).get_or([]) {
				files.append(f"{dir}/{f.path}")
			}
		}
	}

	ms := tool_ms(root.clone())
	scratch := temporary("ms-copy-").get()
	binary := f"{scratch.path()}/program"
	var env = Map[String, String]()
	env.add("MS_COPY_PROBE", "1")
	env.add("MS_CACHE", "off")

	var swept = 0
	var total = 0
	var failing = 0

	for f in files {
		absolute := f"{root}/{f}"
		source := read_file(absolute.clone()).wait().get().decode_utf8() or ""
		var command = List[String]()

		if source.contains("export fn main") {
			command = ["build", absolute.clone(), "-o", binary.clone()]
		} else if source.contains("\ntest ") {
			command = ["test", absolute.clone(), "--match", "no test is selected"]
		} else {
			continue
		}

		if out := run(
			ms.clone(),
			command,
			RunOptions(timeout: seconds(120), env: env.clone()),
		).wait() {
			swept += 1

			sites := copies(out.stderr.decode_utf8() or "")
			if sites.is_empty() { continue }

			failing += 1
			total += sites.length()
			for site in sites { print(f"copy: {f}\t{site}") }
		}
	}

	void change_directory(root).get()
	print(f"swept {swept} programs, {total} object copies in {failing}")

	if swept == 0 {
		print("no program was built")
		return 1
	}

	if total != 0 { return 1 }

	return 0
}
