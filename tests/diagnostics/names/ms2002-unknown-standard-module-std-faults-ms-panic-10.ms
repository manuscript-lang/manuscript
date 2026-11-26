// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	HttpResponse, HttpServerOptions from "@std/net/http.ms",
	network from "@std/net/net.ms",
)

fn run() Void {
	values := [0]
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2002 6:5-6:12 module does not export network; did you mean 'Network'?
