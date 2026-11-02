import expect_equal, expect_true from "@std/test/test.ms"
import (
    parse_media_type,
    format_media_type,
    media_type_for_extension,
    extension_for_media_type,
    parse_headers,
    parse_multipart,
    encode_multipart,
    form_part,
    multipart_boundary,
    MediaType
) from "@std/net/mime.ms"

test "media types parse and format":
    let media = parse_media_type("Text/HTML; Charset=\"utf-8\"; q=\"a\\\"b\"").get()
    try expect_equal(media.essence, "text/html")
    try expect_equal(media.params.get("charset").get(""), "utf-8")
    try expect_equal(media.params.get("q").get(""), "a\"b")
    try expect_equal(
        format_media_type(parse_media_type("text/plain; charset=utf-8").get()),
        "text/plain; charset=utf-8"
    )
    try expect_true(parse_media_type("text").is_error())
    try expect_true(parse_media_type("a/b; x=\"open").is_error())

test "extension table maps both ways":
    try expect_equal(media_type_for_extension(".JSON").get(""), "application/json")
    try expect_equal(media_type_for_extension("png").get(""), "image/png")
    try expect_true(not media_type_for_extension(".nope").is_some())
    try expect_equal(extension_for_media_type("image/svg+xml; x=y").get(""), ".svg")

test "headers fold and look up ignoring case":
    let headers = parse_headers(
        "Subject: hello\r\n  world\r\nX-Tag: a\r\nx-tag: b\r\n\r\nbody: no"
    ).get()
    try expect_equal(headers.get("subject").get(""), "hello world")
    try expect_equal(headers.get_all("X-TAG"), ["a", "b"])
    try expect_equal(headers.fields.length(), 3)
    try expect_true(parse_headers("no colon").is_error())
    try expect_true(parse_headers(" folded first").is_error())

test "multipart round-trips fields and files":
    let parts = [
        form_part("title", "Hello".to_bytes()),
        form_part(
            "upload", "line1\r\nline2".to_bytes(), filename: "a b.txt",
            content_type: "text/plain"
        )
    ]
    let body = encode_multipart(parts, "XyZ")
    let back = parse_multipart(body, "XyZ").get()
    try expect_equal(back.length(), 2)
    try expect_equal(back[0].name, "title")
    try expect_equal(back[0].data.decode_utf8().get(""), "Hello")
    try expect_equal(back[1].filename, "a b.txt")
    try expect_equal(back[1].data.decode_utf8().get(""), "line1\r\nline2")
    try expect_equal(back[1].headers.get("content-type").get(""), "text/plain")

test "multipart rejects a missing closing delimiter":
    try expect_true(parse_multipart("--b\r\n\r\nx".to_bytes(), "b").is_error())
    try expect_true(parse_multipart("junk".to_bytes(), "b").is_error())
    try expect_equal(
        multipart_boundary("multipart/form-data; boundary=abc").get(""), "abc"
    )
    try expect_true(not multipart_boundary("text/plain").is_some())
