// conform: tags=diagnostics
// conform: phase=check
    _server := network().serve(address: "127.0.0.1:0", handler: fn(request) HttpResponse:
        values := [1]
        values.append(2)
        return panic("not executed by lint")
    )
