// conform: tags=control-flow,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/bound-native-calls-omit-none-defaults.ms
import expect_equal from "@std/test/test.ms"

test "omitted none defaults" {
	expect_equal("ab".repeat(count: 2), "abab")?
	expect_equal("ab".pad_start(target_length: 4, padding: "-"), "--ab")?
}
