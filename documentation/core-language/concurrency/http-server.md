+++
title = "HTTP server"
weight = 3
+++

# HTTP server

`serve` listens on an address and runs your handler on every core.

```manuscript
let router = build_router(config)
var server = try serve(":8080", router.handler())
try server.wait()
```

`serve(address, handler, options)` returns an `HttpServer`. `options.cores` limits the runtime to that many threads; none means every core, and `cores: 1` runs the same code on one thread.

- `address()` is the bound address, so `serve(":0", ...)` picks a free port.
- `wait(timeout: ...)` pauses until the server has stopped.
- `close()` stops accepting and drains connections within the options' grace period, then cancels them. `close` itself never waits. SIGINT and SIGTERM do the same.

## How requests run

The accept loop is a promise. Each accepted connection becomes a promise of its own on the least busy thread, where it stays; HTTP/1.1, HTTP/2 and the TLS handshake of `options.tls` run there. Each request runs the handler as a promise owned by its connection. A client disconnect or the request timeout drops that promise, which cancels the handler at its next wait.

The handler, the router and everything they capture are built once and only read by every thread. A handler therefore cannot change shared state. State that changes across requests lives in one owner promise that handlers write to through a `pipe`.

A fault in a handler ends only that request, and the connection answers 500. Request-scoped writes through `HttpExchange` (`send`, `send_headers`, `read`, `close`) are `var fn`, since an exchange belongs to one handler.

## Testing

Start the server and call it in one process:

```manuscript
let server = try serve(":0", handler)
let response = try fetch("http://{server.address()}/").wait()
```

`Router.call` runs a handler directly without a socket.
