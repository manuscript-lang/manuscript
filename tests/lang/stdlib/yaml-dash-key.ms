// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse from "@std/data/yaml.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

// `-` and `?` followed directly by the mapping colon are plain keys, not indicators.
fn number_at(doc YamlValue, key String) String {
	match doc {
		ObjectValue(m) => {
			value := m.get_or(key, YamlValue.Null)
			match value {
				NumberValue(text) => return text.clone()
				_ => return "not a number"
			}
		}
		_ => return "not a mapping"
	}
}

test "a lone dash or question mark can be a mapping key" {
	block := parse("-: 1\n?: 2\nname: 3\n") | expect_ok?
	flow := parse("{-: 4}") | expect_ok?
	void expect_equal(number_at(block, "-"), "1")?
	void expect_equal(number_at(block, "?"), "2")?
	return expect_equal(number_at(flow, "-"), "4")
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
