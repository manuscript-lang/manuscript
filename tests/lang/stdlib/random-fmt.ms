// conform: tags=closures,control-flow,faults,formatter,interfaces,lists,modules,optional,parser,records,stdlib-bytes,stdlib-collections,stdlib-random,stdlib-testing,strings,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/random.ms
import (
	uuid_v4 from "@std/data/uuid.ms",
	choice, float, random_bytes, secure_int, shuffle from "@std/random.ms",
	expect_equal from "@std/test/test.ms",
)

test "random bytes returns the requested count and rejects out-of-range counts" {
	expect_equal((random_bytes(16)?).length(), 16)?
	expect_equal((random_bytes(0)?).length(), 0)?

	invalid Int! := error(Error("random: invalid input", kind: "EINVAL"))
	expect_equal(random_bytes(-1).map(bytes => bytes.length()), invalid)?
}

test "secure_int stays in range and rejects an empty range" {
	invalid Int! := error(Error("random: invalid input", kind: "EINVAL"))
	expect_equal(secure_int(3, 3), invalid)?
	expect_equal((secure_int(-2, 3)?) >= -2 and (secure_int(-2, 3)?) < 3, true)?
	expect_equal((secure_int(-3, -2)?), -3)?
	expect_equal((secure_int(-10, -5)?) < -5, true)?
}

test "uuid_v4 has the version and variant bits" {
	id := uuid_v4()?
	expect_equal(id.length(), 36)?
	expect_equal(id.slice(14, 15), "4")?
	expect_equal(["8", "9", "a", "b"].contains(id.slice(19, 20)), true)?
}

test "float shuffle and choice use operating system entropy" {
	sample := float()?
	expect_equal(sample >= 0.0 and sample < 1.0, true)?

	shuffled := shuffle([1, 2, 3, 4, 5])?
	expect_equal(
		shuffled.sorted(fn(left Int, right Int) Int => left - right),
		[1, 2, 3, 4, 5],
	)?
	expect_equal(choice([7])?, 7)?
	expect_equal(choice(List[Int]())?, null)?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tuuid_v4 from "@std/data/uuid.ms",
// expect-formatted: \tchoice, float, random_bytes, secure_int, shuffle from "@std/random.ms",
// expect-formatted: \texpect_equal from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: test "random bytes returns the requested count and rejects out-of-range counts" {
// expect-formatted: \texpect_equal((random_bytes(16)?).length(), 16)?
// expect-formatted: \texpect_equal((random_bytes(0)?).length(), 0)?
// expect-formatted:
// expect-formatted: \tinvalid Int! := error(Error("random: invalid input", kind: "EINVAL"))
// expect-formatted: \texpect_equal(random_bytes(-1).map(bytes => bytes.length()), invalid)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "secure_int stays in range and rejects an empty range" {
// expect-formatted: \tinvalid Int! := error(Error("random: invalid input", kind: "EINVAL"))
// expect-formatted: \texpect_equal(secure_int(3, 3), invalid)?
// expect-formatted: \texpect_equal((secure_int(-2, 3)?) >= -2 and (secure_int(-2, 3)?) < 3, true)?
// expect-formatted: \texpect_equal((secure_int(-3, -2)?), -3)?
// expect-formatted: \texpect_equal((secure_int(-10, -5)?) < -5, true)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "uuid_v4 has the version and variant bits" {
// expect-formatted: \tid := uuid_v4()?
// expect-formatted: \texpect_equal(id.length(), 36)?
// expect-formatted: \texpect_equal(id.slice(14, 15), "4")?
// expect-formatted: \texpect_equal(["8", "9", "a", "b"].contains(id.slice(19, 20)), true)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "float shuffle and choice use operating system entropy" {
// expect-formatted: \tsample := float()?
// expect-formatted: \texpect_equal(sample >= 0.0 and sample < 1.0, true)?
// expect-formatted:
// expect-formatted: \tshuffled := shuffle([1, 2, 3, 4, 5])?
// expect-formatted: \texpect_equal(
// expect-formatted: \t\tshuffled.sorted(fn(left, right Int) Int => left - right),
// expect-formatted: \t\t[1, 2, 3, 4, 5],
// expect-formatted: \t)?
// expect-formatted: \texpect_equal(choice([7])?, 7)?
// expect-formatted: \texpect_equal(choice(List[Int]())?, null)?
// expect-formatted: }
