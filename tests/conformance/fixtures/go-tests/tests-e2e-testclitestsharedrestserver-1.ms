# conform: tags=control-flow,faults,interfaces,interpolation,modules,records,stdlib-http,stdlib-net,stdlib-testing,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/test_fixture_test.go:140 TestCLITestSharedRESTServer
import {TestHooks, expect_equal, expect_ok} from "@std/testing.ms"
import {HttpServer, HttpRequest, HttpResponse, HttpMethod, headers} from "@std/http.ms"
import network from "@std/net.ms"
type ApiFixture:
    server: HttpServer
fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "shared".to_bytes())
fn make_fixture() ApiFixture:
    return ApiFixture(server: network().serve(address: "127.0.0.1:0", handler: handle).get())
impl TestHooks for ApiFixture:
    fn after_all() Unit:
        self.server.close()
test "first request":
    let response = try expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: ""))
    try expect_equal(response.metadata().status, 200)
test "second request uses same server":
    let response = try expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: ""))
    try expect_equal(response.body, "shared".to_bytes())
