// conform: tags=control-flow,formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/bound-native-calls-omit-none-defaults.ms
import expect_equal, expect_false from "@std/test/test.ms"

test "omitted none defaults":
    if v := "ab".repeat(count: 2):
        expect_equal(v, "abab")?
    else:
        expect_false(not (false))?

    expect_equal("ab".pad_start(target_length: 4, padding: "-"), "--ab")?
