// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

fn failed_initializer() Never {
	impossible Int := panic(message: "initializer cannot return")
}

fn returned_failure() Int {
	return panic(message: "result cannot return")
}

fn endless() Int {
	while true {
		continue
	}
}

test "Never faults propagate through initializers and returned values" {
	expect_contains(
		expect_fault(
			() => {
				impossible := failed_initializer()
			}
		)?,
		"initializer cannot return",
	)?
	expect_contains(
		expect_fault(
			() => {
				impossible := returned_failure()
			}
		)?,
		"result cannot return",
	)?
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 9:23 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS3000 8:1 reachable fallthrough in function returning Never; end every path with 'return <Never>' (or make the last branch return)
// expect-error: MS2001 13:12 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
