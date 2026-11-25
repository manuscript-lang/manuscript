// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"

test "list" {
	values := [1, 2]
	if not (values.length() == 2) {
		return panic(message: "check failed")
	}
}
// expect-error: MS2002 3:8-3:13 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2001 8:16 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
