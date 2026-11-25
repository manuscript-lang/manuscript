// conform: tags=diagnostics,tier-core
// conform: phase=check
import Closeable from "@std/io/closeable.ms"

export fn main() Int {
	return 0
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/io/closeable.ms; Closeable is exported by another standard module, so write: import Closeable from "@std/core.ms"
