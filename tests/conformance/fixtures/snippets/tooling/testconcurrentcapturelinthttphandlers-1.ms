# conform: tags=diagnostics,faults,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
import HttpResponse, HttpServerOptions from "@std/net/http.ms"
import panic from "@std/core.ms"

fn run() Unit:
    let _values = [0]
