// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "several checks" {
	good := 2 + 3
	if good == 5 {
		panic("last check failed")
	}
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 8:9 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
