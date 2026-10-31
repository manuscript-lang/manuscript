# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:35 TestFaultSourceLocations
import TextError from "@std/core.ms"

fn checked(n: Int) Int!TextError:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

fn chain(n: Int) Int!TextError:
    let value = try checked(n)
    return ok(value)

export fn main() Int:
    return chain(9223372036854775807).get()
