# conform: tags=closures,diagnostics,faults,maps,modules,stdlib-faults,stdlib-http,stdlib-net,tier-io
# conform: phase=check
# conform: origin=internal/cli/advisory_lint_test.go:19 TestSafetyAdvisoriesDoNotBecomeCheckErrors
from "@std/net.ms" import network
from "@std/http.ms" import HttpResponse
from "@std/core.ms" import panic

def use() -> Unit:
    let shared = Map[Int, Int]()

    let _server = network().serve(
        address: "127.0.0.1:0",
        handler: lambda (request) -> HttpResponse:
            let seen = shared.length()
            return panic("unreached")
    )
