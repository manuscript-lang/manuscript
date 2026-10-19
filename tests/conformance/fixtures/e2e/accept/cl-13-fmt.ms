# conform: tags=formatter,interpolation,modules,parser,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-13.ms
import {expect_equal} from "@std/testing.ms"

fn echo(value: String) String:
    return value

test "text source forms":
    try expect_equal(echo("\{literal\}"), "\{literal\}")
    try expect_equal("\u{1F600}", "😀")
    try expect_equal("value: {3}", "value: 3")
    let _no_value: Unit = unit
