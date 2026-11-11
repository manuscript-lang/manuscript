// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    let values={"a":1,"b":{1:2},}
    consume(values,other: {})
