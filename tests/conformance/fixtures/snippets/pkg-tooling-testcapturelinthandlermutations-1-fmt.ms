# conform: tags=faults,formatter,modules,parser,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/capture_lint_test.go:10 TestCaptureLintHandlerMutations
from "@std/net.ms" import network
from "@std/http.ms" import HttpResponse
from "@std/core.ms" import panic
