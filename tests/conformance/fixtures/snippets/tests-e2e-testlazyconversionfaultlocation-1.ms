# conform: tags=modules,optional,stdlib-errors,tier-stdlib
# conform: phase=run
# conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation
import {TextError} from "@std/core.ms"
fn crash() TextError:
    return TextError((1 / 0).to_string())
export fn main() Int:
    let value: Optional[Int] = none
    let result = value.ok_or_else(crash)
    return 0
