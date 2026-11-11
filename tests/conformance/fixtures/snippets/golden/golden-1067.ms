// conform: tags=diagnostics
// conform: phase=check
fn work() Unit:
    send(destination: resolve(name: service, region: region), payload: encode(build(records)))
