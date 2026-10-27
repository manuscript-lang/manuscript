# conform: tags=formatter,modules,optional,parser,stdlib-errors,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/conversions_queries_test.go:38 TestLazyConversionFaultLocation
from "@std/core.ms" import TextError

def crash() -> TextError:
    return TextError((1 / "".byte_length()).to_string())

export def main() -> Int:
    let value: Optional[Int] = none
    let _result = value.ok_or_else(crash)
    return 0
