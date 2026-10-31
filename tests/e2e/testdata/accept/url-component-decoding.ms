import decode_component, UrlError from "@std/net.ms"
import expect_equal from "@std/test.ms"

test "component decoding preserves plus Unicode and escaped percent":
    for input in ["", "hello-._~AZ09", "資料+é🕰"]:
        try expect_equal((try decode_component(input)), input)
    try expect_equal((try decode_component("a+b%20c")), "a+b c")
    try expect_equal((try decode_component("%2b%2B")), "++")
    try expect_equal((try decode_component("%C3%A9%2F%E8%B3%87%E6%96%99")), "é/資料")
    try expect_equal((try decode_component("%252F")), "%2F")

test "component decoding rejects malformed escapes and UTF8":
    let invalid: String!UrlError = error(UrlError.InvalidData)
    for input in [
        "%", "%A", "%zz", "prefix%zz", "%FF", "%C0%AF", "%ED%A0%80", "%F4%90%80%80",
        "%E2%82", "prefix%FF", "%é", "%1é", "%FF%zz", "%FF%", "%41%zz", "%41%",
        "%C3%A9%zz"
    ]:
        try expect_equal(decode_component(input), invalid)
