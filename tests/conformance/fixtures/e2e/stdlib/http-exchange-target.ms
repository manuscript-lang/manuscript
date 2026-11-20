// conform: tags=testing,tier-io
// conform: phase=test
import (
	parse_target from "@std/net/exchange.ms",
	expect_equal from "@std/test/test.ms",
)

test "an origin-form target splits the path from the raw query":
	target := parse_target("/a%20b/../c?x=1&y=%2F")?
	expect_equal(target.path, "/c")?
	expect_equal(target.query, "x=1&y=%2F")?

test "dot segments and empty segments clean up and never climb above the root":
	expect_equal(parse_target("/a/../b")?.path, "/b")?
	expect_equal(parse_target("/../..")?.path, "/")?
	expect_equal(parse_target("/a/./b/")?.path, "/a/b/")?
	expect_equal(parse_target("//a///b")?.path, "/a/b")?
	expect_equal(parse_target("/")?.path, "/")?

test "an absolute-form target carries its authority and defaults the path":
	target := parse_target("http://example.com:8080?q=1")?
	expect_equal(target.path, "/")?
	expect_equal(target.query, "q=1")?
	expect_equal(target.host, "example.com:8080")?

test "the asterisk form stays as written and a fragment is dropped":
	expect_equal(parse_target("*")?.path, "*")?
	expect_equal(parse_target("/p#frag")?.path, "/p")?

test "unroutable targets are refused":
	for bad in [
		"/a%2Fb", "/a%2fb", "/a%00b", "/a%zz", "/a b", "/a\tb", "http://u@h/", "/%ff"
	]:
		expect_equal(parse_target(bad).is_error(), true)?
