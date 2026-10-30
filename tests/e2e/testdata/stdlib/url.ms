import expect_equal, expect_false, fail from "@std/test.ms"
import (
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
) from "@std/net.ms"

test "URL canonicalization and relative references":
    let url = try parse("https://EXAMPLE.com:443/a/b?q=1#fragment")
    try expect_false(url.host != "example.com" or url.port != some(443))
    try expect_equal((try format(url)), "https://example.com:443/a/b?q=1#fragment")
    try expect_equal(
        (url | try resolve("../c") | try format), "https://example.com:443/c"
    )
    try expect_equal(encode_component("a b/é"), "a%20b%2F%C3%A9")
    try expect_equal((try decode_component("a%20b%2F%C3%A9")), "a b/é")

test "URL query retains duplicate keys empty values and spaces":
    let entries = try parse_query("a=1&a=2&empty=&space=hello+world")
    try expect_false(entries.length() != 4 or entries.get(3).value != "hello world")
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
        let bad = Url(
            base.scheme.clone(), base.host.clone(), base.port, base.path.clone(),
            query.clone(), ""
        )
        if format(bad) != invalid: return fail("query {query}")

    let good = Url(
        base.scheme.clone(), base.host.clone(), base.port, base.path.clone(), "a=%41&b",
        ""
    )
    try expect_equal((try format(good)), "http://h/p?a=%41&b")

test "URL parse rejects malformed hosts and queries and keeps an empty authority":
    let invalid: Result[Url, UrlError] = error(UrlError.InvalidData)
    for text in ["http://host:80:80/", "http://h/p?q=a b", "http://h/p?q=%zz"]:
        if parse(text) != invalid: return fail("accepted {text}")

    let empty = try parse("http://")
    try expect_equal((try format(empty)), "http://")
    try expect_equal((empty | try format | try parse), empty)

test "URL format and resolve reject invalid schemes and hostless relative paths":
    let invalid_text: Result[String, UrlError] = error(UrlError.InvalidInput)
    let invalid_url: Result[Url, UrlError] = error(UrlError.InvalidInput)

    for scheme in [
        "", "1http", "http:", "http:other", "http/other", "http?query", "http#fragment"
    ]:
        let bad = Url(scheme.clone(), "host", none, "/path", "", "")
        if format(bad) != invalid_text: return fail("invalid scheme accepted: {scheme}")

        try expect_equal(resolve(bad, "/next"), invalid_url)

    let relative = Url("custom", "", none, "relative", "", "")
    try expect_equal(format(relative), invalid_text)
    try expect_equal(resolve(relative, "/next"), invalid_url)

    for text in ["custom:/path", "custom+v1.2://host/path", "file:///path", "http://"]:
        let original = try parse(text)
        if (original | try format | try parse) != original: return fail(
            "hierarchical URL round trip: {text}"
        )

    let uppercase = Url("HTTP", "host", none, "/path", "", "")
    try expect_equal((uppercase | try format | try parse).scheme, "http")
    try expect_equal((try resolve(uppercase, "/next")).scheme, "http")
