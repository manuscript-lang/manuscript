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
import panic from "@std/faults.ms"

test "URL canonicalization and relative references":
    let url = try parse("https://EXAMPLE.com:443/a/b?q=1#fragment")
    if url.host != "example.com" or url.port != some(443): return panic("host and port")
    if (try format(url)) != "https://example.com:443/a/b?q=1#fragment": return panic(
        "URL format"
    )
    if ((url | try resolve("../c") | try format) != "https://example.com:443/c"): return panic(
        "relative reference"
    )
    if encode_component("a b/é") != "a%20b%2F%C3%A9": return panic("component escaping")
    if (try decode_component("a%20b%2F%C3%A9")) != "a b/é": return panic(
        "component decoding"
    )

test "URL query retains duplicate keys empty values and spaces":
    let entries = try parse_query("a=1&a=2&empty=&space=hello+world")
    if entries.length() != 4 or entries.at(3).get().value != "hello world": return panic(
        "query values"
    )
    if format_query(entries) != "a=1&a=2&empty=&space=hello+world": return panic(
        "query order"
    )

    let limited: Result[List[QueryEntry], UrlError] = error(UrlError.LimitExceeded)
    if parse_query("a=1&b=2", 1) != limited: return panic("query limit")

    let invalid: Result[String, UrlError] = error(UrlError.InvalidData)
    if decode_component("%zz") != invalid: return panic("malformed escape")

test "URL query skips empty segments":
    if (try parse_query("&a=1&&b=2&") | format_query) != "a=1&b=2": return panic(
        "empty segments kept"
    )
    if not (try parse_query("&&")).is_empty(): return panic("only separators")

    let bounded = try parse_query("a=1&&b=2", 2)
    if bounded.length() != 2: return panic("empty segments counted")

test "URL format rejects queries that would not round trip":
    let base = try parse("http://h/p")
    let invalid: Result[String, UrlError] = error(UrlError.InvalidInput)

    for query in ["a#b", "a b", "%zz", "a%2"]:
        let bad = Url(base.scheme, base.host, base.port, base.path, query, "")
        if format(bad) != invalid: return panic("query {query}")

    let good = Url(base.scheme, base.host, base.port, base.path, "a=%41&b", "")
    if (try format(good)) != "http://h/p?a=%41&b": return panic("valid query")

test "URL parse rejects malformed hosts and queries and keeps an empty authority":
    let invalid: Result[Url, UrlError] = error(UrlError.InvalidData)
    for text in ["http://host:80:80/", "http://h/p?q=a b", "http://h/p?q=%zz"]:
        if parse(text) != invalid: return panic("accepted {text}")
    let empty = try parse("http://")
    if (try format(empty)) != "http://": return panic("empty authority text")
    if (empty | try format | try parse) != empty: return panic(
        "empty authority round trip"
    )

test "URL format and resolve reject invalid schemes and hostless relative paths":
    let invalid_text: Result[String, UrlError] = error(UrlError.InvalidInput)
    let invalid_url: Result[Url, UrlError] = error(UrlError.InvalidInput)

    for scheme in [
        "", "1http", "http:", "http:other", "http/other", "http?query", "http#fragment"
    ]:
        let bad = Url(scheme, "host", none, "/path", "", "")
        if format(bad) != invalid_text: return panic(
            "invalid scheme accepted: {scheme}"
        )
        if resolve(bad, "/next") != invalid_url: return panic("invalid base scheme")

    let relative = Url("custom", "", none, "relative", "", "")
    if format(relative) != invalid_text: return panic("relative path became a hostname")
    if resolve(relative, "/next") != invalid_url: return panic("relative base accepted")

    for text in ["custom:/path", "custom+v1.2://host/path", "file:///path", "http://"]:
        let original = try parse(text)
        if (original | try format | try parse) != original: return panic(
            "hierarchical URL round trip: {text}"
        )

    let uppercase = Url("HTTP", "host", none, "/path", "", "")
    if (uppercase | try format | try parse).scheme != "http": return panic(
        "uppercase scheme rejected"
    )
    if (try resolve(uppercase, "/next")).scheme != "http": return panic(
        "uppercase base scheme rejected"
    )
