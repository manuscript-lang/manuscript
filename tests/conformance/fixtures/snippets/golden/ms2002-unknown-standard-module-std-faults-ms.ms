// conform: tags=diagnostics
// conform: phase=check
import nope from "@std/faults.ms"

fn f() Void {
	return
}
// expect-error: MS2002 3:8-3:12 unknown standard module @std/faults.ms
