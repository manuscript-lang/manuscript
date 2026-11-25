// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:44 TestFormatParagraphs
fn first() Int => return 1

import (
	Other from "./other.ms",
	Value from "./value.ms",
)

fn last() Int => return 2
// expect-error: MS2002 6:1 cannot find module ./other.ms (looked for other.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
