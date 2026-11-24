// conform: tags=testing,tier-io
// conform: phase=test
// A listener accepts a connection without binding it to a thread, and a promise placed
// with
// `Placement.Spread` adopts and serves it, so one listener feeds every core.
import (
	Placement,
	Promise,
	PromiseOptions,
	promise,
	wait_all from "@std/concurrency/promise.ms",
	Connection, Listener, PendingConnection, connect, listen from "@std/net/net.ms",
	expect_equal, expect_error, expect_true from "@std/test/test.ms",

	recv from "./support/conn.ms",
)

fn echo(var pending: PendingConnection) Void!:
	var conn = pending.adopt()?
	chunk := recv(conn, 2.seconds())?
	data := chunk
	if data != null:
		conn.output.write(data)?
	return conn.close()

fn serve_spread(var listener: Listener, count: Int) Void!:
	var served: List[Promise[Void]] = []

	for i in 0..count:
		var pending = listener.accept_pending(2.seconds()).wait()?
		served.append(
			promise(
				fn: echo(pending),
				options: PromiseOptions(placement: Placement.Spread)
			)
		)

	for handler in served:
		handler.wait()?

fn ask(address: String, text: String) String!:
	var client = connect(address, timeout: 2.seconds()).wait()?
	client.output.write(text.to_bytes())?

	reply := recv(client, 2.seconds())?
	void client.close()

	data := reply
	if data != null: return ok(data.decode_utf8() or "")

	return ok("")

test "pending connections are served by promises spread over the threads":
	var listener = listen("127.0.0.1:0")?
	address := listener.address()
	serving := promise(fn: serve_spread(listener, 16))
	var asking: List[Promise[String]] = []

	for i in 0..16:
		target := address.clone()
		asking.append(promise(fn: ask(target, f"hello {i}")))

	replies := wait_all(asking)?
	for i in 0..16:
		expect_equal(replies[i], f"hello {i}")?
	serving.wait()?

test "a pending connection adopts once and closing it unadopted closes the socket":
	var listener = listen("127.0.0.1:0")?
	var client = connect(listener.address(), timeout: 2.seconds()).wait()?
	var pending = listener.accept_pending(2.seconds()).wait()?
	var conn = pending.adopt()?
	cause := pending.adopt() | expect_error?
	expect_equal(cause.kind, "EBADF")?
	void conn.close()

	var second = connect(listener.address(), timeout: 2.seconds()).wait()?
	var dropped = listener.accept_pending(2.seconds()).wait()?
	dropped.close()?
	expect_true((recv(second, 2.seconds())?) == null)?
	client.close()?

test "accepting a pending connection on a closed listener reports it":
	var listener = listen("127.0.0.1:0")?
	listener.close()?
