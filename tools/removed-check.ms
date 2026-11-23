// Removed-spelling check (`make removed-check`): every spelling the language or
// standard library removed or renamed has a snippet in tests/removed/. A snippet starts
// with
//   // removed: <the old spelling>
//   // use: <text the error must contain, naming the new spelling>
//   // fix: <text the file must contain after `ms check --fix`>, or `none: <why>`
// and the check fails unless `ms check` rejects the snippet with an error that contains
// the
// `use` text, and `ms check --fix` rewrites the snippet so the text appears and `ms check`
// passes. `none:` is for a removal no mechanical edit can carry. Add a snippet in the
// same change that removes or renames a spelling. MS names the ms to run (default
// .artifacts/build/ci/src/cli/ms). Usage: ms run tools/removed-check.ms
import (
	working_directory from "@std/os/env.ms",
	GlobOptions, glob, read_file, temporary, write_file from "@std/os/fs.ms",
	RunOptions, run from "@std/os/process.ms",
	seconds from "@std/time.ms",

	tool_ms from "./lib.ms",
)

// The text after `// <key>: ` on a header line, or empty.
fn header(source: String, key: String) String:
	prefix := f"// {key}: "
	for line in source.lines():
		if line.starts_with(prefix): return line.slice(
			prefix.length(),
			line.length(),
		).trim()
	return ""

// The snippet without its header lines, so a header cannot satisfy a text check.
fn body(source: String) String:
	var kept = List[String]()

	for line in source.lines():
		if (
			line.starts_with("// removed: ")
			or line.starts_with("// use: ")
			or line.starts_with("// fix: ")
		): continue

		kept.append(line.clone())

	return kept.join("\n")

fn main() Int:
	root := working_directory().get()
	ms := tool_ms(root.clone())
	var failing = 0
	var seen = 0

	for f in glob("tests/removed", GlobOptions(patterns: ["*.ms"])).get_or([]):
		path := f"{root}/tests/removed/{f.path}"
		source := read_file(path.clone()).wait().get().decode_utf8() or ""
		old := header(source, "removed")
		want := header(source, "use")
		fixed := header(source, "fix")
		seen += 1

		if old == "" or want == "" or fixed == "":
			print(
				f"{f.path}: needs '// removed:', '// use:' and '// fix:' header lines"
			)
			failing += 1
			continue

		out := run(ms.clone(), ["check", path], RunOptions(timeout: seconds(60))).wait().get()
		text := out.stderr.decode_utf8() or ""

		if out.exit_code == 0:
			print(f"{f.path}: '{old}' is accepted; a removed spelling must be an error")
			failing += 1
		else if (
			fixed.starts_with("none:")
			and fixed.slice(5, fixed.length()).trim() == ""
		):
			print(f"{f.path}: 'fix: none:' needs a reason")
			failing += 1
		else if not text.contains(want):
			print(f"{f.path}: the error for '{old}' does not name '{want}'")
			failing += 1
		else if not fixed.starts_with("none:"):
			scratch := temporary("ms-removed-").get()
			copy := f"{scratch.path()}/snippet.ms"
			write_file(copy.clone(), body(source), replace: true).wait().get()

			applied := run(
				ms.clone(),
				["check", "--fix", copy.clone()],
				RunOptions(timeout: seconds(60)),
			).wait().get()
			result := read_file(copy).wait().get().decode_utf8() or ""

			if applied.exit_code != 0 or not result.contains(fixed):
				print(
					f"{f.path}: 'ms check --fix' does not rewrite '{old}' to '{fixed}'"
				)
				failing += 1

	print(f"checked {seen} removed spellings, {failing} failing")
	if seen == 0 or failing != 0: return 1

	return 0
