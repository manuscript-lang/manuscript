from "@std/fs.ms" import relative_path
from "@std/net.ms" import http_url
from "@std/testing.ms" import expect_equal
from "@std/core.ms" import TextError

test "relative_path rejects escapes in both spellings":
    for bad in [
        "", "/etc/passwd", "\\windows", "C:file", "../x", "a/../../x", "a\\..\\x",
        "a\u{0}b", ".."
    ]:
        if relative_path(bad.clone()).is_ok(): return error(
            TextError(f"accepted {bad}")
        )
    for good in ["a", "a/b.txt", "..a/b", "a/.hidden", "./a"]:
        if relative_path(good.clone()).is_error(): return error(
            TextError(f"rejected {good}")
        )

test "relative_path join needs an absolute root":
    let rel = try relative_path("a/b.txt")
    if rel.under("srv").is_ok(): return error(TextError("accepted relative root"))

test "http_url accepts only http and https with a host":
    for bad in [
        "file:///etc/passwd", "javascript:alert(1)", "ftp://x.org/",
        "data:text/plain,hi", "/relative", ""
    ]:
        if http_url(bad.clone()).is_ok(): return error(TextError(f"accepted {bad}"))

    let url = try http_url("HTTPS://Example.com/a?b=1")
    try expect_equal(url.url.host, "example.com")
    try expect_equal(try url.text(), "https://example.com/a?b=1")
