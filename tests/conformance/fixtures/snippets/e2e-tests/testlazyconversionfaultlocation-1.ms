# conform: tags=modules,optional,stdlib-errors,tier-stdlib
# conform: phase=run
# conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation

fn crash() Error:
    return Error((1 / "".byte_length()).to_string())

export fn main() Int:
    let value: Int? = none
    let _result = value.ok_or_else(crash)
    return 0
