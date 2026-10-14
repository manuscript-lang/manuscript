import {
    parse,
    format,
    resolve,
    encode_component,
    decode_component,
    parse_query,
    format_query,
    QueryEntry,
    UrlError
} from "@std/url.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "URL canonicalization and relative references":
    let url = value(parse("https://EXAMPLE.com:443/a/b?q=1#fragment"))
    if url.host != "example.com" or url.port != some(443): return panic(
        "host and port"
    )
    if value(format(url)) != "https://example.com:443/a/b?q=1#fragment": return panic(
        "URL format"
    )
    if (
        value(
            format(
                value(resolve(base: url, reference: "../c"))
            )
        ) != "https://example.com:443/c"
    ): return panic("relative reference")
    if encode_component("a b/é") != "a%20b%2F%C3%A9": return panic("component escaping")
    if value(decode_component("a%20b%2F%C3%A9")) != "a b/é": return panic(
        "component decoding"
    )

test "URL query retains duplicate keys empty values and spaces":
    let entries = value(parse_query(text: "a=1&a=2&empty=&space=hello+world"))
    if entries.length() != 4 or entries.at(3).unwrap().value != "hello world": return panic(
        "query values"
    )
    if format_query(entries) != "a=1&a=2&empty=&space=hello+world": return panic(
        "query order"
    )

    let limited: Result[List[QueryEntry], UrlError] = error(
        UrlError.LimitExceeded
    )
    if parse_query(
        text: "a=1&b=2",
        max_entries: 1
    ) != limited: return panic("query limit")

    let invalid: Result[String, UrlError] = error(UrlError.InvalidData)
    if decode_component("%zz") != invalid: return panic("malformed escape")

test "URL query skips empty segments":
    let entries = value(parse_query(text: "a=1&&b=2&"))
    if entries.length() != 2 or format_query(entries) != "a=1&b=2": return panic(
        "empty query segments"
    )
