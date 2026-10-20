# conform: tags=diagnostics,faults,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
import network from "@std/net.ms"
import { HttpResponse, HttpServerOptions } from "@std/http.ms"
import panic from "@std/faults.ms"
fn run() Unit:
    let values = [0]
