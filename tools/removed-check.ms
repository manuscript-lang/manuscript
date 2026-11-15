// Removed-spelling check (`make removed-check`): every spelling the language or
// standard library removed or renamed has a snippet in tests/removed/. A snippet starts
// with
//   // removed: <the old spelling>
//   // use: <text the error must contain, naming the new spelling>
// and the check fails unless `ms check` rejects the snippet and its error contains the
// `use` text. Add a snippet in the same change that removes or renames a spelling.
// MS names the ms to run (default target/release/ms). Usage: ms run
// tools/removed-check.ms
import (
	working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// The text after `// <key>: ` on a header line, or empty.
fn header(source: String, key: String) String:
	prefix := "// {key}: "
	for line in source.lines():
		if line.starts_with(prefix): return line.slice(
			prefix.length(),
			line.length(),
		).get("").trim()
	return ""

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root.clone())
	var failing = 0
	var seen = 0

	for f in glob("tests/removed", GlobOptions(patterns: ["*.ms"])).get([]):
		path := "{root}/tests/removed/{f.path}"
		source := read_file(path.clone()).wait().get().decode_utf8().get("")
		old := header(source, "removed")
		want := header(source, "use")
		seen += 1

		if old == "" or want == "":
			print("{f.path}: needs '// removed:' and '// use:' header lines")
			failing += 1
			continue

		out := run(ms.clone(), ["check", path], RunOptions(timeout: seconds(60))).wait().get()
		text := out.stderr.decode_utf8().get("")

		if out.exit_code == 0:
			print("{f.path}: '{old}' is accepted; a removed spelling must be an error")
			failing += 1
		else if not text.contains(want):
			print("{f.path}: the error for '{old}' does not name '{want}'")
			failing += 1

	print("checked {seen} removed spellings, {failing} failing")
	if seen == 0 or failing != 0: return 1

	return 0
