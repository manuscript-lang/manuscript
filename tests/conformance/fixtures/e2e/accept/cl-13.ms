// conform: tags=interpolation,modules,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/cl-13.ms
import expect_equal from "@std/test/test.ms"

fn echo(value: String) String:
    return value

test "text source forms":
    expect_equal(echo("\{literal\}"), "\{literal\}")?
    expect_equal("\u{1F600}", "😀")?
    expect_equal("value: {3}", "value: 3")?

    _no_value: Unit := unit
