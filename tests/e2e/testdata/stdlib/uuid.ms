import expect_equal, expect_ok, expect_true, fail from "@std/test/test.ms"
import sleep, milliseconds, now from "@std/os/time.ms"
import (
    uuid_v5,
    uuid_v7,
    uuid_version,
    namespace_dns,
    namespace_url,
    UuidError
) from "@std/data/uuid.ms"
import ulid, token from "@std/os/random.ms"

test "uuid_v5 matches reference vectors":
    (uuid_v5(namespace_dns, "python.org") | try expect_ok) | try expect_equal(
        "886313e1-3b8a-5372-9b90-0c9aee199e5d"
    )
    (uuid_v5(namespace_url, "https://example.com/a?b=1") | try expect_ok) | try expect_equal(
        "c0c04f10-f8d2-5af0-8144-36577bf29414"
    )
    (uuid_v5(namespace_dns, "") | try expect_ok) | try expect_equal(
        "4ebd0208-8328-5d69-8c44-ec50939c0967"
    )
    (uuid_v5("00000000-0000-0000-0000-000000000000", "héllo") | try expect_ok) | try expect_equal(
        "73447f16-bb71-5922-b638-a95b21012057"
    )

test "uuid_v5 accepts an uppercase namespace and rejects malformed ones":
    (uuid_v5("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "python.org") | try expect_ok) | try expect_equal(
        "886313e1-3b8a-5372-9b90-0c9aee199e5d"
    )

    for bad in [
        "", "nope", "6ba7b8109dad11d180b400c04fd430c8",
        "6ba7b810-9dad-11d1-80b4-00c04fd430cZ"
    ]:
        let result = uuid_v5(bad, "x")
        if let _ = result: return fail("accepted {bad}")

test "uuid_version reads the version of valid text only":
    uuid_version("886313e1-3b8a-5372-9b90-0c9aee199e5d") | try expect_equal(5)
    uuid_version("886313E1-3B8A-5372-9B90-0C9AEE199E5D") | try expect_equal(5)
    uuid_version("886313e1-3b8a-5372-1b90-0c9aee199e5d") | try expect_equal(none)
    uuid_version("not a uuid") | try expect_equal(none)

test "uuid_v7 is a version-7 uuid that sorts by creation time":
    let first = (uuid_v7() | try expect_ok)
    uuid_version(first) | try expect_equal(7)
    first.length() | try expect_equal(36)
    sleep(milliseconds(3))

    let second = (uuid_v7() | try expect_ok)
    (first < second) | try expect_true

test "ulid has 26 Crockford characters and sorts by creation time":
    let first = (ulid() | try expect_ok)
    first.length() | try expect_equal(26)
    for ch in first.chars():
        if not "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains(ch): return fail(
            "bad character {ch}"
        )
    sleep(milliseconds(3))

    let second = (ulid() | try expect_ok)
    (first < second) | try expect_true

test "ulid starts with the current time in milliseconds":
    let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    let id = (ulid() | try expect_ok)
    var millis = 0
    for ch in id.take(10).chars():
        millis = millis * 32 + alphabet.index_of(ch).get(0)

    let moment = now()
    let current = moment.seconds * 1000 + moment.nanos / 1000000
    ((current - millis) < 5000 and millis <= current) | try expect_true

test "token is URL-safe base64 of the requested size":
    let secret = (token() | try expect_ok)
    secret.length() | try expect_equal(43)
    (token(16) | try expect_ok).length() | try expect_equal(22)
    (token(0) | try expect_ok) | try expect_equal("")
    for ch in secret.chars():
        if ch == "+" or ch == "/" or ch == "=": return fail("not url safe")

    let again = (token() | try expect_ok)
    (secret != again) | try expect_true
