// conform: tags=diagnostics
// conform: phase=check
import TestHooks, expect_equal, expect_ok from "@std/test/test.ms"
import HttpServer, HttpRequest, HttpResponse, HttpMethod, headers from "@std/net/http.ms"
import network from "@std/net/net.ms"
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
    response := expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: ""))?
    expect_equal(response.metadata().status, 200)?
test "second request uses same server":
    response := expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: ""))?
    expect_equal(response.body, "shared".to_bytes())?
