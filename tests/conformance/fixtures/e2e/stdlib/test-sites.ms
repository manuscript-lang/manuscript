// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	caller_site,
	catch_fault,
	expect_equal,
	expect_error,
	expect_fault,
	expect_none,
	expect_ok,
	expect_some,
	expect_true,
	fail,
	repr from "@std/test/test.ms",
)

fn site_of(failure: Error) String:
	return failure.details.get_or("site", "")

fn good() Int!:
	return ok(3)

fn bad() Int!:
	return error(Error("bad"))

fn nothing() String?:
	return none

fn wrapped(actual: Bool, site: String = caller_site()) Unit!:
	return expect_true(actual, site)

test "a failed expectation names the line of its call":
	failure := expect_error(expect_true(false))?
	expect_equal(failure.message, "expected true, got false")?
	expect_true(site_of(failure).ends_with("test-sites.ms:34:5"))?

test "a wrapper that forwards its site reports its own caller":
	failure := expect_error(wrapped(false))?
	expect_true(site_of(failure).ends_with("test-sites.ms:39:5"))?

test "an explicit site wins":
	failure := expect_error(expect_true(false, "elsewhere:1:1"))?
	expect_equal(site_of(failure), "elsewhere:1:1")?

test "expectations return the original payload":
	expect_equal(expect_some("a")?, "a")?
	expect_equal(expect_ok(good())?, 3)?

	cause := expect_error(bad())?
	expect_equal(cause.message, "bad")?
	expect_none(nothing())?

test "repr quotes strings and spells out collections":
	expect_equal(repr("a"), "\"a\"")?
	expect_equal(repr(["a", "b"]), "[\"a\", \"b\"]")?
	expect_equal(repr(7), "7")?

test "catch_fault returns a fault message and none for a normal return":
	message := expect_some(catch_fault(fn: panic("boom")))?
	expect_equal(message, "boom")?
	expect_none(catch_fault(fn: unit))?
	expect_equal(expect_fault(fn: panic("again"))?, "again")?

test "fail builds an error with a site":
	failure := expect_error(fail("custom"))?
	expect_equal(failure.message, "custom")?
	expect_true(site_of(failure).ends_with("test-sites.ms:66:5"))?

test "source location constants name their use site":
	// `fail` on this line reports the same line as `__LINE__`, so the test keeps its meaning when lines move.
	expect_true(site_of(expect_error(fail("here"))?).contains(":{__LINE__}:"))?
	expect_true(__FILE__.ends_with("test-sites.ms"))?
	expect_true(site_of(expect_error(fail("here"))?).contains("{__FILE__}:{__LINE__}:"))?
