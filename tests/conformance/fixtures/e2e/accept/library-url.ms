# conform: tags=modules,stdlib-testing,stdlib-url,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/library-url.ms
import {expect_equal} from "@std/testing.ms"
import parse from "@std/url.ms"
import format from "@std/url.ms"
import encode_component from "@std/url.ms"
import decode_component from "@std/url.ms"
import resolve from "@std/url.ms"
import UrlError from "@std/url.ms"

fn verify_url() Result[Unit, Error]:
    let url = try parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")
    (try format(value: url)) | try expect_equal(
        expected: "https://example.com/a%2Fb?q=x#frag"
    )
    let next = try resolve(base: url, reference: "../next")
    (try format(value: next)) | try expect_equal(expected: "https://example.com/next")
    encode_component(text: "a+b/@") | try expect_equal(expected: "a%2Bb%2F%40")
    (try decode_component(text: "%C3%A9")) | try expect_equal(expected: "é")
    return ok(unit)

test "URLs preserve escaped path structure":
    try verify_url()
