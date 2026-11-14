+++
title = "HTTP server"
weight = 3
+++

# HTTP server

Use `serve` to run an HTTP handler, then test it with the same client APIs your application uses. This complete test starts a server on a free local port, makes one request and checks its response. The server closes when the test ends.

Save as `server_test.ms` and run `ms test server_test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import serve from "@std/net/net.ms"
import buffered, text from "@std/net/http.ms"
import fetch from "@std/net/fetch.ms"
import expect_equal from "@std/test/test.ms"

test "serve a greeting":
    handler := buffered(fn request: text(200, "Hello, Manuscript!"))
    server := serve("127.0.0.1:0", handler)?
    response := fetch("http://{server.address()}/").wait()?
    expect_equal(response.head.status, 200)?
    expect_equal(response.text()?, "Hello, Manuscript!")?
```

```text
RUN server_test.ms::serve a greeting
PASS server_test.ms::serve a greeting
1 tests, 0 failed
```

`buffered` adapts a function returning a complete `HttpResponse` into the streaming handler that `serve` accepts. `text` builds a text response. Use `HttpExchange` directly when you need to read or send a body incrementally.

## Keep an application server running

In a function returning `Unit!`, keep the server alive with `wait()`:

```manuscript
server := serve("127.0.0.1:8080", handler)?
server.wait()?
```

Here `handler` is built as in the test. The wait lasts until shutdown or a server error; SIGINT and SIGTERM initiate shutdown.

`serve(address, handler, options)` returns an `HttpServer`; `options` is optional and defaults to `HttpServerOptions()`. An `HttpResponse` likewise needs only `status` and `body`; `headers` defaults to empty. `options.cores` limits the runtime to that many threads; none means every core, and `cores: 1` runs the same code on one thread.

- `address()` is the bound address, so `serve(":0", ...)` picks a free port.
- `wait(timeout: ...)` pauses until the server has stopped.
- `close()` stops accepting and drains connections within the options' grace period, then cancels them. `close` itself never waits. SIGINT and SIGTERM do the same.

## How requests run

The accept loop is a promise. Each accepted connection becomes a promise of its own on the least busy thread, where it stays; HTTP/1.1, HTTP/2 and the TLS handshake of `options.tls` run there. Each request runs the handler as a promise owned by its connection. A client disconnect or the request timeout drops that promise, which cancels the handler at its next wait.

The handler, the router and everything they capture are built once and only read by every thread. A handler therefore cannot change shared state. State that changes across requests lives in one owner promise that handlers write to through a `pipe`. A pipe's reader ends as soon as no writer is open, so the function that starts the owner keeps one `gate` writer open until the server has closed, and each handler calls `writer()` for its own end ([pipes](streams.md#pipes)). A pipe carries clonable values, so a request that needs an answer from the owner cannot send a reply writer along; let handlers read the owner's data from a file or another read-only source.

A fault in a handler ends only that request, and the connection answers 500. Request-scoped writes through `HttpExchange` (`send`, `send_headers`, `read`, `close`) are `var fn`, since an exchange belongs to one handler.

## Testing routes without a socket

Use `Router.call` to test routing and response behavior directly. Keep a loopback test like the one above for the network boundary. See the [router API](../../standard-library/reference/net/router.ms.md).
