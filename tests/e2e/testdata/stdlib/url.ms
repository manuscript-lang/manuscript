import {
    parse,
    format,
    resolve,
    encode_component,
    decode_component,
    parse_query,
    format_query,
    QueryEntry,
    Url,
    UrlError
} from "@std/url.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "URL canonicalization and relative references":
    let url = value(parse("https://EXAMPLE.com:443/a/b?q=1#fragment"))
    if url.host != "example.com" or url.port != some(443): return panic("host and port")
    if value(format(url)) != "https://example.com:443/a/b?q=1#fragment": return panic(
        "URL format"
    )
    if (
        value(
            format(value(resolve(base: url, reference: "../c")))
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

    let limited: Result[List[QueryEntry], UrlError] = error(UrlError.LimitExceeded)
    if parse_query(text: "a=1&b=2", max_entries: 1) != limited: return panic(
        "query limit"
    )

    let invalid: Result[String, UrlError] = error(UrlError.InvalidData)
    if decode_component("%zz") != invalid: return panic("malformed escape")

test "URL query skips empty segments":
    let entries = value(parse_query(text: "&a=1&&b=2&"))
    if format_query(entries) != "a=1&b=2": return panic("empty segments kept")
    if not value(parse_query(text: "&&")).is_empty(): return panic("only separators")

    let bounded = value(parse_query(text: "a=1&&b=2", max_entries: 2))
    if bounded.length() != 2: return panic("empty segments counted")

test "URL format rejects queries that would not round trip":
    let base = value(parse("http://h/p"))
    let invalid: Result[String, UrlError] = error(UrlError.InvalidInput)

    for query in ["a#b", "a b", "%zz", "a%2"]:
        let bad = Url(
            scheme: base.scheme,
            host: base.host,
            port: base.port,
            path: base.path,
            query: query,
            fragment: ""
        )
        if format(bad) != invalid: return panic("query {query}")

    let good = Url(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        path: base.path,
        query: "a=%41&b",
        fragment: ""
    )
    if value(format(good)) != "http://h/p?a=%41&b": return panic("valid query")
