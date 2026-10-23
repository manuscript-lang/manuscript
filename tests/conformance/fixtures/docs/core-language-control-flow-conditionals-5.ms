# conform: tags=control-flow,diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:59
import {TextError} from "@std/core.ms"

fn port(lookup: Result[Int, TextError]) Int:
    if let value = lookup:
        return value

    return 8080
