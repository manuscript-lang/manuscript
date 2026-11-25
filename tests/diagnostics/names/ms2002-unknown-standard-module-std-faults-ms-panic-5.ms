// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

fn positive(value Int) Int {
	if value > 0 {
		return value
	} else {
		panic("positive value required")
	}
}

fn discard(value Int) Void {
	if not (value > 0) {
		return panic("check failed")
	}
}

test "return contracts" {
	if not (positive(3) == 3) {
		return panic("check failed")
	}

	discard(1)
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 9:9 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS3000 5:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
// expect-error: MS2001 15:16 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS2001 21:16 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
