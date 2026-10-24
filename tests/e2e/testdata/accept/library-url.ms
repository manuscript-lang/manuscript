from "@std/testing.ms" import expect_equal
from "@std/net.ms" import parse
from "@std/net.ms" import format
from "@std/net.ms" import encode_component
from "@std/net.ms" import decode_component
from "@std/net.ms" import resolve
from "@std/net.ms" import UrlError

def verify_url() -> Result[Unit, Error]:
    let url = try parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")
    (try format(value: url)) | try expect_equal("https://example.com/a%2Fb?q=x#frag")

    let next = try resolve(base: url, reference: "../next")
    (try format(value: next)) | try expect_equal("https://example.com/next")
    encode_component(text: "a+b/@") | try expect_equal("a%2Bb%2F%40")
    (try decode_component(text: "%C3%A9")) | try expect_equal("é")
    return ok(())

test "URLs preserve escaped path structure":
    try verify_url()
