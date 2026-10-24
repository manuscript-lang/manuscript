# conform: tags=control-flow,diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:59
from "@std/core.ms" import TextError

def port(lookup: Result[Int, TextError]) -> Int:
    if let value = lookup:
        return value

    return 8080
