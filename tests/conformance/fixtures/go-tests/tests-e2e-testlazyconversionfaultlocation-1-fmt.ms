# conform: tags=formatter,modules,optional,parser,stdlib-errors,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation
import {TextError} from "@std/errors.ms"
fn crash() TextError:
    return TextError((1 / 0).to_string())
export fn main() Int:
    let value: Optional[Int] = none
    let result = value.ok_or_else(crash)
    return 0
