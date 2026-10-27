# conform: tags=diagnostics,faults,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
from "@std/net.ms" import network
from "@std/http.ms" import HttpResponse, HttpServerOptions
from "@std/core.ms" import panic

def run() -> Unit:
    let _values = [0]
