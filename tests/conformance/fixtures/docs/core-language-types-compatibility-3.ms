# conform: tags=diagnostics,modules,records,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:69

fn known() Result[Int, Error]:
    let number: Int = try Result[Int, Error].ok(1)
    return ok(number)

fn unknown() Result[Int, Error]:
    # Rejected: the try operand's error type is undetermined.
    let number: Int = try ok(1)
    return ok(number)
