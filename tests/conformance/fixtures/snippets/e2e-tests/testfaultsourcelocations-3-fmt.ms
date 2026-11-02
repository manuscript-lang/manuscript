# conform: tags=control-flow,faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:35 TestFaultSourceLocations

fn checked(n: Int) Int!Error:
    if n < 0:
        return error(Error("negative"))

    return ok(n + 1)

fn chain(n: Int) Int!Error:
    let value = try checked(n)
    return ok(value)

export fn main() Int:
    return chain(9223372036854775807).get()
