// conform: tags=diagnostics
// conform: phase=check
    values := {"hits": 0}
    _server := network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.add(key: "hits", value: 1)
        return panic("not executed by lint")
    )
