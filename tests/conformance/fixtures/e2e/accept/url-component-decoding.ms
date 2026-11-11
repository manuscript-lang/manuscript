// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	decode_component from "@std/net/url.ms",
	expect_equal from "@std/test/test.ms",
)

test "component decoding preserves plus Unicode and escaped percent":
	for input in ["", "hello-._~AZ09", "資料+é🕰"]:
		expect_equal((decode_component(input)?), input)?
	expect_equal((decode_component("a+b%20c")?), "a+b c")?
	expect_equal((decode_component("%2b%2B")?), "++")?
	expect_equal((decode_component("%C3%A9%2F%E8%B3%87%E6%96%99")?), "é/資料")?
	expect_equal((decode_component("%252F")?), "%2F")?

test "component decoding rejects malformed escapes and UTF8":
	invalid: String! := error(Error("URL: invalid data", kind: "EBADMSG"))
	for input in [
		"%", "%A", "%zz", "prefix%zz", "%FF", "%C0%AF", "%ED%A0%80", "%F4%90%80%80",
		"%E2%82", "prefix%FF", "%é", "%1é", "%FF%zz", "%FF%", "%41%zz", "%41%",
		"%C3%A9%zz"
	]:
		expect_equal(decode_component(input), invalid)?
