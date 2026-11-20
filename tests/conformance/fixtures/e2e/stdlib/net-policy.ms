// conform: tags=stdlib-net,tier-stdlib,testing
// conform: phase=test
import (
	address_allowed,
	host_allowed,
	listen_allowed,
	narrow,
	unix_allowed,
	unrestricted from "@std/net/policy.ms",
	expect_false, expect_true from "@std/test/test.ms",
)

test "hosts and prefixes":
	p := narrow(unrestricted(), ["Example.COM."], ["10.0.0.0/8"], false)?
	expect_true(host_allowed(p, "example.com"))?
	expect_true(host_allowed(p, "10.1.2.3"))?
	expect_false(host_allowed(p, "other.com"))?
	expect_true(address_allowed(p, "10.9.9.9"))?
	expect_false(address_allowed(p, "11.0.0.1"))?
	expect_false(address_allowed(p, "not an address"))?

	only_hosts := narrow(unrestricted(), ["a.test"], [], false)?
	expect_true(address_allowed(only_hosts, "203.0.113.9"))?

	empty := narrow(unrestricted(), [], [], false)?
	expect_false(address_allowed(empty, "127.0.0.1"))?
	expect_false(host_allowed(empty, "anything"))?
	expect_true(host_allowed(unrestricted(), "anything"))?

test "a child only narrows its parent":
	parent := narrow(unrestricted(), ["a.test", "b.test"], [], true)?
	child := narrow(parent, ["a.test"], [], true)?
	expect_true(host_allowed(child, "a.test"))?
	expect_false(host_allowed(child, "b.test"))?
	expect_false(host_allowed(child, "c.test"))?

test "listening needs permission at every level":
	wide := narrow(unrestricted(), [], ["127.0.0.0/8"], true)?
	expect_true(listen_allowed(wide, "127.0.0.1"))?
	expect_false(listen_allowed(wide, "10.0.0.1"))?
	expect_false(listen_allowed(wide, "localhost"))?

	child := narrow(
		narrow(unrestricted(), [], ["127.0.0.0/8"], false)?,
		[],
		["127.0.0.0/8"],
		true,
	)?
	expect_false(listen_allowed(child, "127.0.0.1"))?
	expect_true(listen_allowed(unrestricted(), "anything"))?

test "an invalid range is an error":
	expect_true(narrow(unrestricted(), [], ["10.0.0.0/33"], false).is_error())?

test "unix sockets need an unrestricted network":
	expect_true(unix_allowed(unrestricted()))?
	expect_false(unix_allowed(narrow(unrestricted(), ["a.test"], [], false)?))?
