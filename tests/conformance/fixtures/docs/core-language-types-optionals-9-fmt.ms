# conform: tags=formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:111
fn port_number(text: String) Result[Int, Error]:
    let port = try text.parse_int().ok_or()
    return ok(port)
