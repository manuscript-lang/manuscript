// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	HttpResponse from "@std/net/http.ms",
	network from "@std/net/net.ms",
)

fn use() Void {
	shared := Map[Int, Int]()

	_server := network().serve(
		address: "127.0.0.1:0",
		handler: fn(request) HttpResponse {
			shared.add(key: 1, value: 2)
			return panic("unreached")
		}
	)
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2002 6:5-6:12 module does not export network; did you mean 'Network'?
// expect-error: MS2001 12:16 unknown binding network; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
// expect-error: MS3080 14:21 cannot infer callback parameter request; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
// expect-error: MS2001 16:20 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
