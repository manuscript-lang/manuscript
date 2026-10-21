# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:116
import panic from "@std/core.ms"

fn check_positive(value: Int) Unit:
    if not (value > 0):
        return panic(message: "check failed")

fn missing_value() Int:
    return panic(message: "Required value is missing")
