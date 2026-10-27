from "@std/testing.ms" import expect_equal, expect_true
from "@std/html.ms" import parse
from "@std/crypto.ms" import sha256, sha512
from "@std/random.ms" import entropy, secure_int, uuid_v4, shuffle, choice, float
from "@std/collections.ms" import map_from_entries
from "@std/io.ms" import stdout, stderr
from "@std/time.ms" import clock, wall_clock
from "@std/math.ms" import max
from "@std/bytes.ms" import Bytes

test "stdlib natives bound to a name behave like the call":
    let digest = sha256
    let wide = sha512
    try expect_equal(digest(Bytes([1])), sha256(Bytes([1])))
    try expect_equal(wide(Bytes([1])).length(), 64)

    let page = parse
    try expect_true(page("<p>x</p>").is_ok())

    let pairs = map_from_entries[Int, Int]
    try expect_equal(pairs([MapEntry(1, 2)]).get_or(1, 0), 2)

    let biggest = max[Int]
    try expect_equal(biggest(1, 3), 3)

test "random natives bound to a name draw from the entropy":
    let source = entropy()
    let int_in = secure_int
    let id = uuid_v4
    let mix = shuffle[Int]
    let pick = choice[Int]
    let draw = float
    let n = int_in(source, 5, 6).get()
    try expect_equal(n, 5)
    try expect_equal(id(source).get().length(), 36)
    try expect_equal(mix(source, [1, 2, 3]).get().length(), 3)
    try expect_true(pick(source, [7]).get().is_some())
    try expect_true(draw(source).get() < 1.0)

test "handle natives bound to a name are usable":
    let out = stdout
    let err = stderr
    let wall = wall_clock
    let mono = clock
    try expect_true(out().flush().is_ok())
    try expect_true(err().flush().is_ok())
    try expect_true(wall().now().unix_seconds() > 0)

    let first = mono().now()
    let second = mono().now()
    try expect_true(second.difference(first).to_nanoseconds() >= 0)
