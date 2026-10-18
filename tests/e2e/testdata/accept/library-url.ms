import panic from "@std/faults.ms"
import parse from "@std/url.ms"
import format from "@std/url.ms"
import encode_component from "@std/url.ms"
import decode_component from "@std/url.ms"
import resolve from "@std/url.ms"
import UrlError from "@std/url.ms"

fn verify_url() Result[Unit, UrlError]:
    let url = try parse(text: "https://EXAMPLE.COM/a%2Fb?q=x#frag")
    if not (try format(value: url) == "https://example.com/a%2Fb?q=x#frag"):
        return panic(message: "check failed")

    let next = try resolve(base: url, reference: "../next")
    if not (try format(value: next) == "https://example.com/next"):
        return panic(message: "check failed")
    if not (encode_component(text: "a+b/@") == "a%2Bb%2F%40"):
        return panic(message: "check failed")
    if not (try decode_component(text: "%C3%A9") == "é"):
        return panic(message: "check failed")

    return ok(unit)

test "URLs preserve escaped path structure":
    let expected: Result[Unit, UrlError] = ok(unit)
    if not (verify_url() == expected):
        return panic(message: "check failed")
