// conform: tags=control-flow,formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/bound-native-calls-omit-none-defaults.ms
import expect_equal from "@std/test/test.ms"

test "omitted none defaults" {
	expect_equal("ab".repeat(count: 2), "abab")?
	expect_equal("ab".pad_start(target_length: 4, padding: "-"), "--ab")?
}
