+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## HttpRequest

Kind: record.

```text
HttpRequest: HttpRequest
field method: String
field path: String
field query: String
field headers: Map[String, Bytes]
field body: Bytes
```

## HttpResponse

Kind: record.

```text
HttpResponse: HttpResponse
field status: Int
field headers: Map[String, String]
field body: Bytes
```

## HttpServer

Kind: contract.

```text
HttpServer: HttpServer
operation address: fn()->String
operation close: fn()->Unit
operation wait: fn()->Result[Unit, IoError]
```

## Network

Kind: contract.

```text
Network: Network
operation close: fn()->Unit
operation serve: fn(address: String, handler: fn(request: HttpRequest)->HttpResponse, limit: Int, max_body_bytes: Int, max_response_bytes: Int, timeout: Duration, grace: Duration)->Result[HttpServer & Shareable, IoError]
```

