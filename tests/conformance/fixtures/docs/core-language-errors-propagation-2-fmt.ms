# conform: tags=formatter,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/propagation.md:24

fn prepare() Result[Unit, Error]: ok(unit)

fn ready_label() Result[String, Error]:
    try prepare()
    return ok("ready")
