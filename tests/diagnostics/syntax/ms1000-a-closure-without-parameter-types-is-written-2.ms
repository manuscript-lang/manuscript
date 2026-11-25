// conform: tags=diagnostics
// conform: phase=check
    _server := network().serve_stream(address: "127.0.0.1:0", handler: fn(exchange) {
        values.append(1)
        return ok()
    }
    , options: HttpServerOptions(tls: null))
// expect-error: MS1000 3:85-3:86 a closure without parameter types is written without 'fn': x => { ... }, (a, b) => { ... } or () => { ... }
