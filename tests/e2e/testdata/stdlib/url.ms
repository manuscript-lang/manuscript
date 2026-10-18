import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
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

test "URL canonicalization and relative references":
    let url = (parse("https://EXAMPLE.com:443/a/b?q=1#fragment") | try expect_ok)
    (url.host != "example.com" or url.port != some(443)) | try expect_false
    format(url) | try expect_ok | try expect_equal(
        expected: "https://example.com:443/a/b?q=1#fragment"
    )
    try expect_false(
        (
            (
                format(
                    (
                        resolve(
                            base: url,
                            reference: "../c"
                        ) | try expect_ok
                    )
                ) | try expect_ok
            ) != "https://example.com:443/c"
        )
    )
    encode_component("a b/é") | try expect_equal(expected: "a%20b%2F%C3%A9")
    decode_component("a%20b%2F%C3%A9") | try expect_ok | try expect_equal(
        expected: "a b/é"
    )

test "URL query retains duplicate keys empty values and spaces":
    let entries = (
        parse_query(text: "a=1&a=2&empty=&space=hello+world") | try expect_ok
    )
    (entries.length() != 4 or entries.at(3).unwrap().value != "hello world") | try expect_false
    format_query(entries) | try expect_equal(
        expected: "a=1&a=2&empty=&space=hello+world"
    )
    let limited: Result[List[QueryEntry], UrlError] = error(UrlError.LimitExceeded)
    parse_query(text: "a=1&b=2", max_entries: 1) | try expect_equal(expected: limited)
    let invalid: Result[String, UrlError] = error(UrlError.InvalidData)
    decode_component("%zz") | try expect_equal(expected: invalid)

test "URL query skips empty segments":
    let entries = (parse_query(text: "&a=1&&b=2&") | try expect_ok)
    format_query(entries) | try expect_equal(expected: "a=1&b=2")
    ((parse_query(text: "&&") | try expect_ok).is_empty()) | try expect_true
    let bounded = (parse_query(text: "a=1&&b=2", max_entries: 2) | try expect_ok)
    bounded.length() | try expect_equal(expected: 2)

test "URL format rejects queries that would not round trip":
    let base = (parse("http://h/p") | try expect_ok)
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
        if format(bad) != invalid: return fail("query {query}")

    let good = Url(
        scheme: base.scheme,
        host: base.host,
        port: base.port,
        path: base.path,
        query: "a=%41&b",
        fragment: ""
    )
    format(good) | try expect_ok | try expect_equal(expected: "http://h/p?a=%41&b")
