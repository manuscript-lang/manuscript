+++
title = "A JSON API"
weight = 13
+++

# A JSON API

Route requests, read a typed JSON body, answer with JSON, and test the routes without opening a socket.

## Define routes and test them

Save as `api_test.ms` and run `ms test api_test.ms`. Each handler reads what it needs from the exchange and replies with a value; `json` encodes it and sets the content type. `Router.call` runs a request through the routes and returns the response, so the test needs no port.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import parse from "@std/data/json.ms"
import (
    HttpExchange, HttpMethod, HttpRequest, HttpResponse, headers, json, read_body, reply, text from "@std/net/http.ms",
)
import RouteParams, Router from "@std/net/router.ms"
import expect_equal from "@std/test/test.ms"

type Greeting:
    message: String

type Numbers:
    values: List[Int]

type Total:
    total: Int

fn greet(var exchange: HttpExchange, params: RouteParams) Void!:
    name := params.get_or("name", "world")
    return reply(exchange, json(200, Greeting(message: f"Hello, {name}!"))?)

fn sum(var exchange: HttpExchange, params: RouteParams) Void!:
    body := read_body(exchange)?
    numbers := parse[Numbers](ok_or(body.decode_utf8(), Error("not UTF-8", kind: "EBADMSG"))?)
    if numbers.is_error():
        return reply(exchange, text(400, "expected a list named values"))
    return reply(exchange, json(200, Total(total: numbers.get().values.sum()))?)

fn api() Router:
    var router = Router()
    router.get("/hello/:name", greet).get()
    router.post("/sum", sum).get()
    return router

fn request(method: HttpMethod, path: String, body: String) HttpRequest:
    return HttpRequest(method: method, path: path, query: "", headers: headers(), body: body.to_bytes())

fn body_of(response: HttpResponse) String:
    return response.body.decode_utf8() or ""

test "greet by name":
    response := api().call(request(HttpMethod.Get, "/hello/Ada", ""))?
    expect_equal(response.status, 200)?
    expect_equal(body_of(response), "{\"message\":\"Hello, Ada!\"}")?

test "sum a list":
    response := api().call(request(HttpMethod.Post, "/sum", "{\"values\":[1,2,3]}"))?
    expect_equal(body_of(response), "{\"total\":6}")?

test "reject a body of the wrong shape":
    response := api().call(request(HttpMethod.Post, "/sum", "{\"values\":\"x\"}"))?
    expect_equal(response.status, 400)?
```

```text
RUN api_test.ms::greet by name
PASS api_test.ms::greet by name
RUN api_test.ms::sum a list
PASS api_test.ms::sum a list
RUN api_test.ms::reject a body of the wrong shape
PASS api_test.ms::reject a body of the wrong shape
3 tests, 0 failed
```

An unknown path answers 404 and a known path with another method answers 405 with an `Allow` header. Handlers only read what they capture. State that changes between requests belongs in one owner promise, as described in [the HTTP server guide](../core-language/concurrency/http-server.md#how-requests-run).

## Serve the API

Pass the router to `serve` in a function returning `Void!`, with `main` handing it an address. `wait()` returns when the server stops; SIGINT and SIGTERM stop it gracefully.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import serve from "@std/net/net.ms"

fn main() Void!:
    server := serve("0.0.0.0:8080", api().handler())?
    server.wait()?
```

Here `api` is the function from the test above. Add `access_log` and `request_id` middleware from `@std/net/router.ms` to log each request with its id.
