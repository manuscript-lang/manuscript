import (
    certificate, private_key from "./support/certificates.ms",
    expect_equal, expect_ok from "@std/test/test.ms",
    HttpExchange, HttpServerOptions, reply, text from "@std/net/http.ms",
    serve from "@std/net/net.ms",
    memory_usage from "@std/os/system.ms",
    PromiseOptions from "@std/concurrency/promise.ms",
    fetcher, FetcherOptions, FetchOptions from "@std/net/fetch.ms",
    sleep from "@std/time.ms",
    TlsOptions from "@std/net/tls.ms",
)

fn handler(var exchange: HttpExchange) Unit!:
    if exchange.path() == "/hang":
        try sleep(30.seconds()).wait()
        return ok(unit)

    return reply(var exchange, text(200, "ok"))

test "requests cancelled on a shared HTTP/2 connection release their streams":
    let server_tls = TlsOptions(
        certificate_pem: certificate(), private_key_pem: private_key(),
        alpn: ["h2", "http/1.1"]
    )
    let client_tls = TlsOptions(roots_pem: certificate(), alpn: ["h2", "http/1.1"])
    let server = serve(
        address: "127.0.0.1:0", handler: handler,
        options: HttpServerOptions(tls: server_tls)
    ) | try expect_ok
    let client = fetcher(FetcherOptions(tls: client_tls)) | try expect_ok
    let base = "https://{server.address()}"
    let first = client.fetch(
        "{base}/ok", FetchOptions(timeout: none)
    ).wait() | try expect_ok
    first.head.protocol | try expect_equal("HTTP/2.0")

    // Each cancelled request used to stay open on the connection, so the peer's stream limit
    // filled and later requests failed.
    for i in 0..400:
        let _ = client.fetch("{base}/hang", FetchOptions(timeout: none)).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()

    let after = client.fetch(
        "{base}/ok", FetchOptions(timeout: 5.seconds())
    ).wait() | try expect_ok
    after.text() | try expect_ok | try expect_equal("ok")

    let before = (memory_usage() | try expect_ok).heap_used
    for i in 0..1000:
        let _ = client.fetch("{base}/hang", FetchOptions(timeout: none)).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()

    // A cancelled stream's queue and headers leaked about 600 bytes each.
    let grown = (memory_usage() | try expect_ok).heap_used - before
    if grown > 1000 * 64: return error(
        Error("heap grew {grown} bytes over 1000 cancelled requests")
    )
