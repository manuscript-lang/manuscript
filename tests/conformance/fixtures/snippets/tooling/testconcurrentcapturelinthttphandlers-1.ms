// conform: tags=diagnostics,faults,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
// conform: phase=check
// conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
import (
	panic from "@std/core.ms",
	HttpResponse, HttpServerOptions from "@std/net/http.ms",
)

fn run() Void {
	_values := [0]
}
// expect-exit: 0
