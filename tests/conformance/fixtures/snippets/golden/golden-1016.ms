// conform: tags=diagnostics
// conform: phase=check
    values := {"hits": 0}
    _server := network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.get("hits")
        return panic("not executed by lint")
    )
