import (
	Version, parse from "@std/data/semver.ms",
	expect_equal, expect_false, expect_ok, fail from "@std/test/test.ms",
)

fn failure(result: Version!) Error!:
	match result:
		ok(_): return error(Error("accepted"))
		error(cause): return ok(cause)

test "semver parses and formats every component":
	version := (parse(text: "1.2.3-alpha.1+build.5") | try expect_ok)
	(version.major != 1 or version.minor != 2 or version.patch != 3) | try expect_false
	version.prerelease | try expect_equal(["alpha", "1"])
	version.build | try expect_equal(["build", "5"])
	version.format() | try expect_equal("1.2.3-alpha.1+build.5")
	(parse(text: "0.0.0") | try expect_ok).format() | try expect_equal("0.0.0")

test "semver rejects malformed text":
	bad := [
		"", "1", "1.2", "1.2.3.4", "v1.2.3", " 1.2.3", "01.2.3", "1.2.-3", "1.2.3-",
		"1.2.3+", "1.2.3-01", "1.2.3-a..b", "1.2.3-a_b", "1.2.3+é"
	]
	for text in bad:
		if (
			(try failure(parse(text: text))) != Error(
				"semver: invalid data", kind: "EBADMSG"
			)
		): return fail("category {text}")

test "semver reports numbers beyond Int":
	(try failure(parse(text: "99999999999999999999.0.0"))) | try expect_equal(
		Error("semver: value out of range", kind: "ERANGE")
	)

test "semver orders by precedence":
	ordered := [
		"1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
		"1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0",
		"2.0.0", "10.0.0"
	]
	var i = 0

	while i < ordered.length():
		var j = 0

		while j < ordered.length():
			var expected = 0
			if i < j: expected = -1
			if i > j: expected = 1

			left := ordered[i]
			right := ordered[j]
			if (
				(parse(text: left) | try expect_ok).compare(
					parse(text: right) | try expect_ok
				) != expected
			): return fail("order {left} {right}")

			j += 1

		i += 1

test "semver ignores build metadata and compares huge numeric identifiers":
	a := (parse(text: "1.0.0+a") | try expect_ok)
	b := (parse(text: "1.0.0+b") | try expect_ok)
	a.compare(b) | try expect_equal(0)

	small := (parse(text: "1.0.0-99999999999999999999") | try expect_ok)
	large := (parse(text: "1.0.0-100000000000000000000") | try expect_ok)
	small.compare(large) | try expect_equal(-1)
	Error("semver: value out of range", kind: "ERANGE").message | try expect_equal(
		"semver: value out of range"
	)

test "semver keeps hyphens in pre-release and rejects extra plus signs":
	version := (parse(text: "1.2.3-alpha-1") | try expect_ok)
	version.format() | try expect_equal("1.2.3-alpha-1")
	(try failure(parse(text: "1.2.3+a+b"))) | try expect_equal(
		Error("semver: invalid data", kind: "EBADMSG")
	)
