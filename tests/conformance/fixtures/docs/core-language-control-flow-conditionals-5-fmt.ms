# conform: tags=control-flow,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/conditionals.md:59
import TextError from "@std/core.ms"

fn port(lookup: Result[Int, TextError]) Int:
    if let value = lookup:
        return value

    return 8080
