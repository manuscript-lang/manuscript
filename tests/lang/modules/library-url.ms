// conform: tags=formatter,modules,stdlib-testing,stdlib-url,testing,tier-stdlib,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/library-url.ms
import (
	decode_component, encode_component, format, parse, resolve from "@std/net/url.ms",
	expect_equal from "@std/test/test.ms",
)

fn verify_url() Void! {
	url := parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")?
	(format(value: url)?) | expect_equal("https://example.com/a%2Fb?q=x#frag")?

	next := resolve(base: url, reference: "../next")?
	(format(value: next)?) | expect_equal("https://example.com/next")?
	encode_component(text: "a+b/@") | expect_equal("a%2Bb%2F%40")?
	(decode_component(text: "%C3%A9")?) | expect_equal("é")?
}

test "URLs preserve escaped path structure" {
	verify_url()?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
