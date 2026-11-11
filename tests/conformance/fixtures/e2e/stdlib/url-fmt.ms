// conform: tags=alternatives,control-flow,faults,formatter,interpolation,lists,modules,optional,parser,stdlib-testing,stdlib-url,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/url.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import parse, format, resolve, encode_component, decode_component, parse_query, format_query, QueryEntry, Url from "@std/net/url.ms"

test "URL canonicalization and relative references":
    url := parse("https://EXAMPLE.com:443/a/b?q=1#fragment")?
    expect_false(url.host != "example.com" or url.port != 443)?
    expect_equal((format(url)?), "https://example.com:443/a/b?q=1#fragment")?
    expect_equal(
        (url | resolve("../c")? | format?), "https://example.com:443/c"
    )?
    expect_equal(encode_component("a b/é"), "a%20b%2F%C3%A9")?
    expect_equal((decode_component("a%20b%2F%C3%A9")?), "a b/é")?

test "URL query retains duplicate keys empty values and spaces":
    entries := parse_query("a=1&a=2&empty=&space=hello+world")?
    expect_false(entries.length() != 4 or entries.get(3).value != "hello world")?
    expect_equal(format_query(entries), "a=1&a=2&empty=&space=hello+world")?

    limited: List[QueryEntry]! := error(
        Error("URL: limit exceeded", kind: "EOVERFLOW")
    )
    expect_equal(parse_query("a=1&b=2", 1), limited)?

    invalid: String! := error(
        Error("URL: invalid data", kind: "EBADMSG")
    )
    expect_equal(decode_component("%zz"), invalid)?

test "URL query skips empty segments":
    expect_equal((parse_query("&a=1&&b=2&")? | format_query), "a=1&b=2")?
    expect_false(not (parse_query("&&")?).is_empty())?

    bounded := parse_query("a=1&&b=2", 2)?
    expect_equal(bounded.length(), 2)?

test "URL format rejects queries that would not round trip":
    base := parse("http://h/p")?
    invalid: String! := error(
        Error("URL: invalid input", kind: "EINVAL")
    )

    for query in ["a#b", "a b", "%zz", "a%2"]:
        bad := Url(
            base.scheme.clone(), base.host.clone(), base.port, base.path.clone(),
            query.clone(), ""
        )
        if format(bad) != invalid: return fail("query {query}")

    good := Url(
        base.scheme.clone(), base.host.clone(), base.port, base.path.clone(), "a=%41&b",
        ""
    )
    expect_equal((format(good)?), "http://h/p?a=%41&b")?

test "URL parse rejects malformed hosts and queries and keeps an empty authority":
    invalid: Url! := error(
        Error("URL: invalid data", kind: "EBADMSG")
    )
    for text in ["http://host:80:80/", "http://h/p?q=a b", "http://h/p?q=%zz"]:
        if parse(text) != invalid: return fail("accepted {text}")

    empty := parse("http://")?
    expect_equal((format(empty)?), "http://")?
    expect_equal((empty | format? | parse?), empty)?

test "URL format and resolve reject invalid schemes and hostless relative paths":
    invalid_text: String! := error(
        Error("URL: invalid input", kind: "EINVAL")
    )
    invalid_url: Url! := error(
        Error("URL: invalid input", kind: "EINVAL")
    )

    for scheme in [
        "", "1http", "http:", "http:other", "http/other", "http?query", "http#fragment"
    ]:
        bad := Url(scheme.clone(), "host", none, "/path", "", "")
        if format(bad) != invalid_text: return fail("invalid scheme accepted: {scheme}")

        expect_equal(resolve(bad, "/next"), invalid_url)?

    relative := Url("custom", "", none, "relative", "", "")
    expect_equal(format(relative), invalid_text)?
    expect_equal(resolve(relative, "/next"), invalid_url)?

    for text in ["custom:/path", "custom+v1.2://host/path", "file:///path", "http://"]:
        original := parse(text)?
        if (original | format? | parse?) != original: return fail(
            "hierarchical URL round trip: {text}"
        )

    uppercase := Url("HTTP", "host", none, "/path", "", "")
    expect_equal((uppercase | format? | parse?).scheme, "http")?
    expect_equal((resolve(uppercase, "/next")?).scheme, "http")?
