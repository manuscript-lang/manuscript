// conform: tags=diagnostics
// conform: phase=check
    values := [0]
    _server := network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values.append(1)
        return panic("not executed by lint")
    )
