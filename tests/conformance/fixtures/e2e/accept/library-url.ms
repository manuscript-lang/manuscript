// conform: tags=modules,stdlib-testing,stdlib-url,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/library-url.ms
import expect_equal from "@std/test/test.ms"
import parse from "@std/net/url.ms"
import format from "@std/net/url.ms"
import encode_component from "@std/net/url.ms"
import decode_component from "@std/net/url.ms"
import resolve from "@std/net/url.ms"

fn verify_url() Unit!:
    let url = try parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")
    (try format(value: url)) | try expect_equal("https://example.com/a%2Fb?q=x#frag")

    let next = try resolve(base: url, reference: "../next")
    (try format(value: next)) | try expect_equal("https://example.com/next")
    encode_component(text: "a+b/@") | try expect_equal("a%2Bb%2F%40")
    (try decode_component(text: "%C3%A9")) | try expect_equal("é")

test "URLs preserve escaped path structure":
    try verify_url()
