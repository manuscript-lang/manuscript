// conform: tags=diagnostics,modules,mutation,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/tooling/lint_program_test.go:11 TestSemanticLintUsesReadsAndControlFlow
import ListEntry from "@std/collections/collections.ms"

fn answer() Int {
	_unused := 1
	var _written = 2
	_written = 3
	return 0
	return 1
}
// expect-error: MS2003 4:8-4:17 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
