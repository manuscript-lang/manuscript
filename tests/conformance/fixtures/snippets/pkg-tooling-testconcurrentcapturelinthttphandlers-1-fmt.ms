# conform: tags=faults,formatter,modules,parser,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/capture_lint_test.go:101 TestConcurrentCaptureLintHTTPHandlers
import network from "@std/net.ms"
import {HttpResponse, HttpServerOptions} from "@std/http.ms"
import panic from "@std/core.ms"

fn run() Unit:
    let _values = [0]
