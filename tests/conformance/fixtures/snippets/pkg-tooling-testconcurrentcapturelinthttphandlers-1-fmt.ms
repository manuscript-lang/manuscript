# conform: tags=faults,formatter,modules,parser,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
from "@std/net.ms" import network
from "@std/http.ms" import HttpResponse, HttpServerOptions
from "@std/core.ms" import panic

def run() -> Unit:
    let values = [0]
