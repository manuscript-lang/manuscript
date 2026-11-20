// Prints the lexical lint findings of each file named on the command line, one per line
// as
// `file:line:column: CODE severity message`. Usage:
//   ms run tools/ms/lint.ms --link libmstool.a -- file.ms...
import (
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",

	Finding from "./lint/finding.ms",
	lint_interpolation from "./lint/interpolation.ms",
	lint_matches from "./lint/matches.ms",
	lint_terse from "./lint/terse.ms",
	lint_source from "./lint/text.ms",
)

fn show(finding: Finding) String:
	return f"{finding.file}:{finding.line}:{finding.column}: {finding.code} {finding.severity} {finding.message}"

fn main() Int:
	var status = 0

	for path in arguments():
		bytes := read_file(path).wait()

		match bytes:
			ok(data):
				text := data.decode_utf8().get_or("")
				for finding in lint_source(path, text): print(show(finding))
				for finding in lint_matches(path, text): print(show(finding))
				for finding in lint_terse(path, text): print(show(finding))
				for finding in lint_interpolation(path, text): print(show(finding))
			error(_failure):
				print(f"{path}: cannot read")
				status = 1

	return status
