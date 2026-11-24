// conform: tags=testing,tier-io
// conform: phase=test
import (
	Datagram, bind_datagram, connect, listen from "@std/net/net.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

// A missing or malformed port is invalid input (EINVAL), not an I/O failure (EIO).
fn kind_of(e: Error) String:
	return e.kind.clone() or ""

test "malformed host and port text returns EINVAL":
	for address in [
		"abc", "", "127.0.0.1:", "127.0.0.1:99999", "127.0.0.1:-1", "127.0.0.1:abc",
		"::1:0"
	]:
		l := listen(address) | expect_error?
		void expect_equal(kind_of(l), "EINVAL")?

		d := bind_datagram(address) | expect_error?
		void expect_equal(kind_of(d), "EINVAL")?

		c := connect(address).wait() | expect_error?
		void expect_equal(kind_of(c), "EINVAL")?

	return ok()

test "a datagram sent to a malformed address returns EINVAL":
	var sock = bind_datagram("127.0.0.1:0") | expect_ok?
	e := sock.output.write(Datagram("x".to_bytes(), "127.0.0.1:99999")) | expect_error?
	return expect_equal(kind_of(e), "EINVAL")
