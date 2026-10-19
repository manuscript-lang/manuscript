# conform: tags=control-flow,diagnostics,faults,modules,stdlib-faults,tier-stdlib
# conform: phase=check
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:116
import panic from "@std/faults.ms"

fn check_positive(value: Int) Unit:
    if not (value > 0):
        return panic(message: "check failed")

fn missing_value() Int:
    return panic(message: "Required value is missing")
