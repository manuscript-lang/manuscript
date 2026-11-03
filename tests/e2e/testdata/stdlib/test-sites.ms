import panic from "@std/core.ms"
import (
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
    repr
) from "@std/test/test.ms"

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
    let failure = try expect_error(expect_true(false))
    try expect_equal(failure.message, "expected true, got false")
    try expect_true(site_of(failure).ends_with("test-sites.ms:32:5"))

test "a wrapper that forwards its site reports its own caller":
    let failure = try expect_error(wrapped(false))
    try expect_true(site_of(failure).ends_with("test-sites.ms:37:5"))

test "an explicit site wins":
    let failure = try expect_error(expect_true(false, "elsewhere:1:1"))
    try expect_equal(site_of(failure), "elsewhere:1:1")

test "expectations return the original payload":
    try expect_equal(try expect_some("a"), "a")
    try expect_equal(try expect_ok(good()), 3)

    let cause = try expect_error(bad())
    try expect_equal(cause.message, "bad")
    try expect_none(nothing())

test "repr quotes strings and spells out collections":
    try expect_equal(repr("a"), "\"a\"")
    try expect_equal(repr(["a", "b"]), "[\"a\", \"b\"]")
    try expect_equal(repr(7), "7")

test "catch_fault returns a fault message and none for a normal return":
    let message = try expect_some(catch_fault(fn: panic("boom")))
    try expect_equal(message, "boom")
    try expect_none(catch_fault(fn: unit))
    try expect_equal(try expect_fault(fn: panic("again")), "again")

test "fail builds an error with a site":
    let failure = try expect_error(fail("custom"))
    try expect_equal(failure.message, "custom")
    try expect_true(site_of(failure).ends_with("test-sites.ms:64:5"))
