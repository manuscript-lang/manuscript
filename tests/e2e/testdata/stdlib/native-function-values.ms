import (
    expect_equal, expect_true from "@std/test/test.ms",
    parse from "@std/data/html.ms",
    sha256, sha512 from "@std/crypto.ms",
    uuid_v4 from "@std/data/uuid.ms",
    secure_int, shuffle, choice, float from "@std/random.ms",
    map_from_entries from "@std/collections/collections.ms",
    stdout, stderr from "@std/io/io.ms",
    monotonic, now from "@std/time.ms",
    max from "@std/math/math.ms",
    Bytes from "@std/bytes.ms",
)

test "stdlib natives bound to a name behave like the call":
    digest := sha256
    wide := sha512
    try expect_equal(digest(Bytes([1])), sha256(Bytes([1])))
    try expect_equal(wide(Bytes([1])).length(), 64)

    page := parse
    try expect_true(page("<p>x</p>").is_ok())

    pairs := map_from_entries[Int, Int]
    try expect_equal(pairs([MapEntry(1, 2)]).get_or(1, 0), 2)

    biggest := max[Int]
    try expect_equal(biggest(1, 3), 3)

test "random natives bound to a name draw from the operating system":
    int_in := secure_int
    id := uuid_v4
    mix := shuffle[Int]
    pick := choice[Int]
    draw := float
    n := int_in(5, 6).get()
    try expect_equal(n, 5)
    try expect_equal(id().get().length(), 36)
    try expect_equal(mix([1, 2, 3]).get().length(), 3)
    try expect_true(pick([7]).get().is_some())
    try expect_true(draw().get() < 1.0)

test "handle natives bound to a name are usable":
    out := stdout
    err := stderr
    wall := now
    mono := monotonic
    try out().flush()
    try err().flush()
    try expect_true(wall().unix_seconds() > 0)

    first := mono()
    second := mono()
    try expect_true(second.difference(first).to_nanoseconds() >= 0)
