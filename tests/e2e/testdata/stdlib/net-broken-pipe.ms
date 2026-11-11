import (
	connect, listen from "@std/net/net.ms",
	expect_ok from "@std/test/test.ms",
	sleep from "@std/time.ms",

	send from "./support/conn.ms",
)

// A write to a peer that has gone away must return an error. Without SIGPIPE ignored the
// whole process dies with the signal instead.
test "writing to a closed connection returns an error":
	listener := listen("127.0.0.1:0") | expect_ok?
	var client = connect(listener.address(), timeout: 2.seconds()).wait() | expect_ok?
	var accepted = listener.accept(2.seconds()).wait() | expect_ok?
	client.close()?

	var attempts = 0

	while attempts < 200:
		_ := sleep(10.milliseconds()).wait()
		written := send(var accepted, "ping")

		if _sent := written:
			attempts += 0
		else:
			return ok(unit)

		attempts += 1

	return error(Error("writes to a closed peer never failed"))
