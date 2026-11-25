// conform: tags=testing,tier-io
// conform: phase=test
// The client rejects a response whose status line or Content-Length is malformed,
// whatever the transport library would have accepted, and keeps answering well-formed
// ones.
import (
	Placement, PromiseOptions, promise from "@std/concurrency/promise.ms",
	FetchOptions, fetch from "@std/net/fetch.ms",
	Connection, Listener, listen from "@std/net/net.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	recv from "./support/conn.ms",
)

fn reply_once(var listener Listener, response String) Void! {
	var conn = listener.accept(5.seconds()).wait()?
	_request := recv(conn, 2.seconds())?
	conn.output.write(response.to_bytes())?
	conn.output.flush()?
	return conn.close()
}

fn status_of(response String) Int! {
	var listener = listen("127.0.0.1:0")?
	url := f"http://{listener.address()}/"
	answered := promise(
		() => reply_once(listener, response.clone()),
		options: PromiseOptions(placement: Placement.Here),
	)
	got := fetch(url, FetchOptions(timeout: 5.seconds())).wait()
	void answered.wait()

	response_head := got?
	return ok(response_head.head.status)
}

test "a well-formed response is read" {
	expect_equal(status_of("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")?, 200)?
	expect_equal(status_of("HTTP/1.1 204\r\nContent-Length: 0\r\n\r\n")?, 204)?
	expect_equal(status_of("HTTP/1.1 200 OK\r\nContent-Length: 0002\r\n\r\nok")?, 200)?
}

test "a status code that is not exactly three digits is an error" {
	expect_true(status_of("HTTP/1.1 2000 X\r\nContent-Length: 0\r\n\r\n").is_error())?
	expect_true(status_of("HTTP/1.1 20 X\r\nContent-Length: 0\r\n\r\n").is_error())?
	expect_true(status_of("HTTP/1.1 200X\r\nContent-Length: 0\r\n\r\n").is_error())?
}

test "a Content-Length that does not fit in 63 bits is an error" {
	expect_true(
		status_of(
			"HTTP/1.1 200 OK\r\nContent-Length: 99999999999999999999\r\n\r\nok"
		).is_error()
	)?
	expect_true(
		status_of(
			"HTTP/1.1 200 OK\r\nContent-Length: 9223372036854775808\r\n\r\nok"
		).is_error()
	)?
}
