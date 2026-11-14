// conform: tags=control-flow,faults,formatter,interfaces,interpolation,modules,parser,records,stdlib-http,stdlib-net,stdlib-testing,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=tests/e2e/test_fixture_test.go:140 TestCLITestSharedRESTServer
import TestHooks, expect_equal, expect_ok from "@std/test/test.ms"
import (
    HttpServer,
    HttpRequest,
    HttpResponse,
    HttpMethod,
    headers,
    buffered
) from "@std/net/http.ms"
import RequestOptions, request, serve from "@std/net/net.ms"

type ApiFixture:
    server: HttpServer

fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "shared".to_bytes())

fn make_fixture() ApiFixture:
    return ApiFixture(
        server: serve(address: "127.0.0.1:0", handler: buffered(handle)).get()
    )

fn var ApiFixture.after_all() Unit!:
    self.server.close().get(none)

test "first request":
    response := expect_ok(
        request(
            method: HttpMethod.Get, url: "http://{fixture.server.address()}/",
            options: RequestOptions(headers: headers())
        )
    )?
    expect_equal(response.metadata().status, 200)?

test "second request uses same server":
    response := expect_ok(
        request(
            method: HttpMethod.Get, url: "http://{fixture.server.address()}/",
            options: RequestOptions(headers: headers())
        )
    )?
    expect_equal(response.body, "shared".to_bytes())?
