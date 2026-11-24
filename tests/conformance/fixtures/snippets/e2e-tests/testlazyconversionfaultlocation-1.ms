// conform: tags=modules,optional,stdlib-errors,tier-stdlib
// conform: phase=run
// conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation

fn crash() Error:
    return Error((1 / "".length()).to_string())

fn main() Void:
    value: Int? := null
    _result := ok_or(value, crash())
