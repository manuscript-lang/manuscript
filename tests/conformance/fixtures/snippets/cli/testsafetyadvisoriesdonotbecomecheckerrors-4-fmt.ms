// conform: tags=closures,faults,formatter,maps,modules,parser,stdlib-faults,stdlib-http,stdlib-net,tier-io
// conform: phase=parse
// conform: origin=internal/cli/advisory_lint_test.go:19 TestSafetyAdvisoriesDoNotBecomeCheckErrors
import serve from "@std/net/net.ms"
import HttpResponse, buffered from "@std/net/http.ms"
import panic from "@std/core.ms"

fn use() Unit:
    shared := Map[Int, Int]()

    handle := fn(request) HttpResponse:
        seen := shared.length()
        return panic("unreached")

    _server := serve(address: "127.0.0.1:0", handler: buffered(handle))
