// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	expect_equal from "@std/test/test.ms",
)

fn positive(value Int) Int {
	if value > 0 {
		return value
	} else {
		panic(message: "positive value required")
	}
}

fn discard(value Int) Void {
	return
}

test "return contracts" {
	positive(value: 3) | expect_equal(expected: 3)?
	discard(value: 1) | expect_equal(expected: void)?
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 12:9 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS3000 8:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
