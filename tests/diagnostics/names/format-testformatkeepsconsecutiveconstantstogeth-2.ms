// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/tooling/format/format_test.go:206 TestFormatKeepsConsecutiveConstantsTogether
import ListEntry from "@std/collections/collections.ms"

A := 1
B := 2

fn f() Int {
	return A + B
}
// expect-error: MS2003 4:8-4:17 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
