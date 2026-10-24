# conform: tags=diagnostics,strings,tier-core,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:111
def port_number(text: String) -> Result[Int, Error]:
    let port = try text.parse_int().ok_or()
    return ok(port)
