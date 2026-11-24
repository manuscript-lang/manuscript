// conform: tags=testing,tier-io
// conform: phase=test
// A `Network` is shared between threads on purpose (see `net.ms`, "resolve returns typed
// DNS records"): the main thread stays busy so an idle thread takes the promise.
import (
	promise from "@std/concurrency/promise.ms",
	Network, with_resolver from "@std/net/net.ms",
	expect_contains, expect_ok, expect_true from "@std/test/test.ms",
)

fn open_one(net Network) String!:
	l := net.listen("127.0.0.1:0")?
	return ok(l.address())

test "a network used in a promise on another thread keeps working":
	net := with_resolver("127.0.0.1:53") | expect_ok?
	p := promise(fn: open_one(net))
	var n = 0
	for i in 0..1500000000:
		n += i % 7

	address := p.wait() | expect_ok?
	void expect_true(n > 0)?
	return expect_contains(address, "127.0.0.1:")
