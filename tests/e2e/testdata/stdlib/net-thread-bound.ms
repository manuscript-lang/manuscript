// A native handle built on `Rc` and `RefCell` holds non-atomic state, so using it from
// the thread of another promise is a named fault rather than a data race (#3047). The
// main thread stays busy so an idle thread takes the promise. A `Network` is shared
// between threads on purpose (see `net.ms`, "resolve returns typed DNS records").
import (
	promise from "@std/concurrency/promise.ms",
	HttpHeaders, headers from "@std/net/http.ms",
	Network, with_resolver from "@std/net/net.ms",
	expect_contains, expect_error, expect_ok, expect_true from "@std/test/test.ms",
)

fn open_one(net: Network) String!:
	l := net.listen("127.0.0.1:0")?
	return ok(l.address())

fn names_of(h: HttpHeaders) List[String]!:
	return ok(h.names())

test "http headers used in a promise on another thread fault with the cause":
	h := headers()
	p := promise(fn: names_of(h))
	var n = 0
	for i in 0..1500000000:
		n += i % 7

	cause := p.wait() | expect_error?
	_ := expect_true(n > 0)?
	return expect_contains(cause.message, "different thread")

test "a network used in a promise on another thread keeps working":
	net := with_resolver("127.0.0.1:53") | expect_ok?
	p := promise(fn: open_one(net))
	var n = 0
	for i in 0..1500000000:
		n += i % 7

	address := p.wait() | expect_ok?
	_ := expect_true(n > 0)?
	return expect_contains(address, "127.0.0.1:")
