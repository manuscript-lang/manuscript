// conform: tags=closures,diagnostics,faults,formatter,maps,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
// conform: phase=check,parse
// conform: origin=internal/cli/advisory_lint_test.go:19 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import (
	panic from "@std/core.ms",
	HttpResponse, buffered from "@std/net/http.ms",
	serve from "@std/net/net.ms",
)

fn use() Void {
	shared := Map[Int, Int]()

	handle := fn(request) HttpResponse {
		seen := shared.length()
		return panic("unreached")
	}

	_server := serve(address: "127.0.0.1:0", handler: buffered(handle))
}
// expect-error: MS3080 13:18 cannot infer callback parameter request; provide a type or a known function context: a closure bound to a variable has none, so write the parameter types and result, as in `fn(n Int) Int => n * 2`
