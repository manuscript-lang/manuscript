# conform: tags=formatter,modules,parser,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/errors/propagation.md:24
import {TextError} from "@std/core.ms"
fn prepare() Result[Unit, TextError]: ok(unit)

fn ready_label() Result[String, TextError]:
    try prepare()
    return ok("ready")
