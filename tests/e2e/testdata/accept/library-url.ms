import parse from "@std/url.ms"
import format from "@std/url.ms"
import encode_component from "@std/url.ms"
import decode_component from "@std/url.ms"
import resolve from "@std/url.ms"
import Result from "@std/result.ms"
import LibraryError from "@std/errors.ms"

fn verify_url() -> Result[Unit, LibraryError]:
    let url = try parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")
    assert try format(value: url) == "https://example.com/a%2Fb?q=x#frag"
    let next = try resolve(base: url, reference: "../next")
    assert try format(value: next) == "https://example.com/next"
    assert encode_component(text: "a+b/@") == "a%2Bb%2F%40"
    assert try decode_component(text: "%C3%A9") == "é"
    return ok(value: unit)

test "URLs preserve escaped path structure":
    let expected: Result[Unit, LibraryError] = ok(value: unit)
    assert verify_url() == expected
