import {expect_equal, expect_false, fail} from "@std/testing.ms"
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
    let url = try parse("https://EXAMPLE.com:443/a/b?q=1#fragment")
    try expect_false(url.host != "example.com" or url.port != some(443))
    try expect_equal((try format(url)), "https://example.com:443/a/b?q=1#fragment")
    try expect_equal(
        (url | try resolve("../c") | try format),
        "https://example.com:443/c"
    )
    try expect_equal(encode_component("a b/é"), "a%20b%2F%C3%A9")
    try expect_equal((try decode_component("a%20b%2F%C3%A9")), "a b/é")

test "URL query retains duplicate keys empty values and spaces":
    let entries = try parse_query("a=1&a=2&empty=&space=hello+world")
    try expect_false(
        entries.length() != 4 or entries.at(3).get().value != "hello world"
    )
    try expect_equal(format_query(entries), "a=1&a=2&empty=&space=hello+world")
    let limited: Result[List[QueryEntry], UrlError] = error(UrlError.LimitExceeded)
    try expect_equal(parse_query("a=1&b=2", 1), limited)
    let invalid: Result[String, UrlError] = error(UrlError.InvalidData)
    try expect_equal(decode_component("%zz"), invalid)

test "URL query skips empty segments":
    try expect_equal((try parse_query("&a=1&&b=2&") | format_query), "a=1&b=2")
    try expect_false(not (try parse_query("&&")).is_empty())
    let bounded = try parse_query("a=1&&b=2", 2)
    try expect_equal(bounded.length(), 2)

test "URL format rejects queries that would not round trip":
    let base = try parse("http://h/p")
    let invalid: Result[String, UrlError] = error(UrlError.InvalidInput)

    for query in ["a#b", "a b", "%zz", "a%2"]:
        let bad = Url(base.scheme, base.host, base.port, base.path, query, "")
        if format(bad) != invalid: return fail("query {query}")

    let good = Url(base.scheme, base.host, base.port, base.path, "a=%41&b", "")
    try expect_equal((try format(good)), "http://h/p?a=%41&b")

test "URL parse rejects malformed hosts and queries and keeps an empty authority":
    let invalid: Result[Url, UrlError] = error(UrlError.InvalidData)
    for text in ["http://host:80:80/", "http://h/p?q=a b", "http://h/p?q=%zz"]:
        if parse(text) != invalid: return fail("accepted {text}")
    let empty = try parse("http://")
    try expect_equal((try format(empty)), "http://")
    try expect_equal((empty | try format | try parse), empty)
