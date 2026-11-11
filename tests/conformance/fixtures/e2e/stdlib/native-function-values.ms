// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	map_from_entries from "@std/collections/collections.ms",
	sha256, sha512 from "@std/crypto.ms",
	parse from "@std/data/html.ms",
	uuid_v4 from "@std/data/uuid.ms",
	stderr, stdout from "@std/io/io.ms",
	max from "@std/math/math.ms",
	choice, float, secure_int, shuffle from "@std/random.ms",
	expect_equal, expect_true from "@std/test/test.ms",
	monotonic, now from "@std/time.ms",
)

test "stdlib natives bound to a name behave like the call":
	digest := sha256
	wide := sha512
	expect_equal(digest(Bytes([1])), sha256(Bytes([1])))?
	expect_equal(wide(Bytes([1])).length(), 64)?

	page := parse
	expect_true(page("<p>x</p>").is_ok())?

	pairs := map_from_entries[Int, Int]
	expect_equal(pairs([MapEntry(1, 2)]).get_or(1, 0), 2)?

	biggest := max[Int]
	expect_equal(biggest(1, 3), 3)?

test "random natives bound to a name draw from the operating system":
	int_in := secure_int
	id := uuid_v4
	mix := shuffle[Int]
	pick := choice[Int]
	draw := float
	n := int_in(5, 6).get()
	expect_equal(n, 5)?
	expect_equal(id().get().length(), 36)?
	expect_equal(mix([1, 2, 3]).get().length(), 3)?
	expect_true(pick([7]).get().is_some())?
	expect_true(draw().get() < 1.0)?

test "handle natives bound to a name are usable":
	out := stdout
	err := stderr
	wall := now
	mono := monotonic
	out().flush()?
	err().flush()?
	expect_true(wall().unix_seconds() > 0)?

	first := mono()
	second := mono()
	expect_true(second.difference(first).to_nanoseconds() >= 0)?
