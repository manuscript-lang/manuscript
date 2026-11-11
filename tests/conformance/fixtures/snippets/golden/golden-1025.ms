// conform: tags=diagnostics
// conform: phase=check
    _server := network().serve_stream(address: "127.0.0.1:0", handler: fn(exchange):
        values.append(1)
        return ok(unit)
    , options: HttpServerOptions(tls: none))
