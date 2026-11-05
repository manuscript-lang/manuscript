+++
title = "HTTP server"
weight = 3
+++

# HTTP server

Start a local HTTP server and test its response with a real request. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::serve a greeting\nPASS example.ms::serve a greeting\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import serve from "@std/net/net.ms"
import buffered, text from "@std/net/http.ms"
import fetch from "@std/net/fetch.ms"
import expect_equal from "@std/test/test.ms"

test "serve a greeting":
    let handler = buffered(fn request: text(200, "Hello, Manuscript!"))
    let server = try serve("127.0.0.1:0", handler)
    let response = try fetch("http://{server.address()}/").wait()
    try expect_equal(response.head.status, 200)
    try expect_equal(try response.text(), "Hello, Manuscript!")
```

```sh
ms test example.ms
```

```text
RUN example.ms::serve a greeting
PASS example.ms::serve a greeting
1 tests, 0 failed
```

<a id="keep-an-application-server-running"></a>
<a id="how-requests-run"></a>
<a id="testing-routes-without-a-socket"></a>

- Handle `server.wait()` to stay alive. Close starts shutdown; wait or scope-end drop joins.
- Disconnects/deadlines cancel at waits; handler faults produce HTTP 500. Return explicit responses for expected failures.

Next: [server lifecycle](../../standard-library/reference/net/http.ms.md#httpserver), [router tests](../../standard-library/reference/net/router.ms.md) and [cancellation](promises.md#cancellation).
