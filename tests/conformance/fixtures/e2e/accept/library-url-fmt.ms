// conform: tags=formatter,modules,parser,stdlib-testing,stdlib-url,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/library-url.ms
import (
	decode_component, encode_component, format, parse, resolve from "@std/net/url.ms",
	expect_equal from "@std/test/test.ms",
)

fn verify_url() Unit!:
	url := parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")?
	(format(value: url)?) | expect_equal("https://example.com/a%2Fb?q=x#frag")?

	next := resolve(base: url, reference: "../next")?
	(format(value: next)?) | expect_equal("https://example.com/next")?
	encode_component(text: "a+b/@") | expect_equal("a%2Bb%2F%40")?
	(decode_component(text: "%C3%A9")?) | expect_equal("é")?

test "URLs preserve escaped path structure":
	verify_url()?
