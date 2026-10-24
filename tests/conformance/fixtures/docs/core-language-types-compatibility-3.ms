# conform: tags=diagnostics,modules,records,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:69
from "@std/core.ms" import TextError

def known() -> Result[Int, TextError]:
    let number: Int = try Result[Int, TextError].ok(1)
    return ok(number)

def unknown() -> Result[Int, TextError]:
    # Rejected: the try operand's error type is undetermined.
    let number: Int = try ok(1)
    return ok(number)
