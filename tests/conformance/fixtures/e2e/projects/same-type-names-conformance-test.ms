// conform: tags=alternatives,diagnostics,match,modules,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/same_type_names/conformance_test.ms
import (
	expect_equal from "@std/test/test.ms",

	flip, shifted from "./other.ms",
)

// The same type names in two modules lower to distinct Go types.
type Point {
	x Int
}

enum Mode {
	Off
	On
}

test "same-named records and alternatives stay distinct" {
	expect_equal(Point(1).x, 1)?
	expect_equal(shifted(), 11)?

	match Mode.On {
		Mode.On => expect_equal(flip(), 2)?
		_ => expect_equal(true, false)?
	}
}
// expect-error: MS2002 4:1 cannot find module ./other.ms (looked for other.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
