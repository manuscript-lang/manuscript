// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	promise from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	DnsKind, IpFamily, contains_ip, parse_cidr, parse_ip from "@std/net/ip.ms",
	Connection,
	Datagram,
	DatagramSocket,
	DnsOptions,
	Listener,
	bind_datagram,
	connect,
	connect_unix,
	listen,
	listen_unix,
	resolve_dns,
	restrict,
	with_resolver from "@std/net/net.ms",
	expect_equal, expect_error, expect_false, expect_true from "@std/test/test.ms",

	within from "./support/conn.ms",
)

test "IP parsing CIDR normalization and containment" {
	expect_equal((parse_ip("2001:0db8::1")?).to_string(), "2001:db8::1")?
	expect_equal((parse_cidr("192.0.2.3/24")?).to_string(), "192.0.2.0/24")?
	expect_false(
		not (
			contains_ip(
				parse_cidr("192.0.2.0/24")?,
				parse_ip("192.0.2.255")?,
			)?
		)
	)?
	expect_false((contains_ip(parse_cidr("192.0.2.0/24")?, parse_ip("192.0.3.0")?)?))?
	expect_ip_error("999.1.1.1")?
}

test "TCP loopback writes reads half close and EOF" {
	listener := listen("127.0.0.1:0")?
	var client = connect(listener.address(), timeout: 2.seconds()).wait()?
	var server = listener.accept(2.seconds()).wait()?
	client.output.write("hello".to_bytes())?
	client.output.flush()?
	expect_equal(
		(within(server.input, 2.seconds())?) or panic(
			"called Optional.get() on null"
		),
		"hello".to_bytes(),
	)?
	expect_equal(server.info.peer_address, client.info.local_address)?
	client.output.end()?
	expect_true((within(server.input, 2.seconds())?) == null)?
}

test "a read cancelled by its timeout leaves the stream closable" {
	listener := listen("127.0.0.1:0")?
	var client = connect(listener.address(), timeout: 2.seconds()).wait()?
	_server := listener.accept(2.seconds()).wait()?

	// The peer is silent, so the limit cancels the read mid-park. The borrowed stream
	// still belongs to the caller: closing it afterwards frees the socket once.
	expect_true(within(client.input, 50.milliseconds()).is_error())?
	client.close()?
}

fn accept_all(listener Listener) Void! {
	while true {
		_connection := listener.accept().wait()?
	}
}

test "a promise that accepts on a listener runs where the listener lives" {
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	_accepting := promise(() => accept_all(listener))

	// Accepts and connects register their connections with one network, which is not
	// thread
	// safe: running the accepts on another thread raced these connects and panicked.
	for i in 0..2000 {
		var client = connect(address, timeout: 2.seconds()).wait()?
		client.close()?
	}
}

test "closing the input leaves the output open and closing both ends the connection" {
	listener := listen("127.0.0.1:0")?
	var client = connect(listener.address(), timeout: 2.seconds()).wait()?
	var server = listener.accept(2.seconds()).wait()?

	// Closing only the input does not end the stream the peer reads.
	client.input.end()?
	client.output.write("still open".to_bytes())?
	client.output.flush()?
	expect_equal(
		(within(server.input, 2.seconds())?) or panic(
			"called Optional.get() on null"
		),
		"still open".to_bytes(),
	)?

	// Closing the output too closes the socket: the peer sees the end of the stream.
	client.output.end()?
	expect_true((within(server.input, 2.seconds())?) == null)?
}

test "host names resolve whatever their case" {
	listener := listen("127.0.0.1:0")?
	port := listener.address().split(":").last().clone() or ""
	client := connect(f"LocalHost:{port}", timeout: 2.seconds()).wait()?
	server := listener.accept(2.seconds()).wait()?
	expect_equal(server.info.peer_address, client.info.local_address)?
}

test "an empty Unix socket path is invalid input" {
	expect_equal(
		expect_error(listen_unix(""))?,
		Error("network: invalid input", kind: "EINVAL"),
	)?
	expect_equal(
		expect_error(connect_unix("", timeout: 1.seconds()).wait())?,
		Error("network: invalid input", kind: "EINVAL"),
	)?
}

test "UDP loopback preserves datagram data and sender" {
	var receiver = bind_datagram("127.0.0.1:0")?
	var sender = bind_datagram("127.0.0.1:0")?
	sender.output.write(Datagram("packet".to_bytes(), receiver.address.clone()))?

	packet := (
		(within(receiver.input, 2.seconds())?)
		or panic("called Optional.get() on null")
	)
	expect_false(
		(packet.data != "packet".to_bytes() or packet.address != sender.address)
	)?
}

test "network restriction denies admission and close rejects acquisitions" {
	restricted := restrict([], [], allow_listen: false)?
	var closing = restrict([], [], allow_listen: false)?
	var scoped = restricted
	expect_false(
		(
			(expect_error(scoped.listen("127.0.0.1:0"))?) != Error(
				"network: permission denied",
				kind: "EACCES",
			)
		)
	)?
	scoped.close()
	closing.close()
	expect_false(
		(
			(
				expect_error(
					closing.connect(
						"127.0.0.1:1",
						timeout: 1.seconds(),
					)
				)?
			) != Error("network: resource is closed", kind: "EBADF")
		)
	)?
}

test "typed addresses preserve normalization and reject zones" {
	ip := parse_ip("::ffff:192.0.2.1")?
	expect_false(ip.to_string() != "192.0.2.1" or ip.family() != IpFamily.IPv4)?
	expect_equal((parse_ip("2001:db8::1")?).family(), IpFamily.IPv6)?
	expect_ip_error("fe80::1%eth0")?
	expect_false((contains_ip(parse_cidr("::ffff:192.0.2.0/120")?, ip)?))?
}

fn expect_ip_error(input String) Void! {
	expect_equal(
		(expect_error(parse_ip(input))?),
		Error("network: invalid data", kind: "EBADMSG"),
	)?
}

fn accept_one(l Listener) Int {
	r := l.accept(2.seconds()).wait()

	if r.is_ok() {
		void r.get().close()
		return 1
	}

	return 0
}

test "a promise accepts on a listener it owns" {
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	a := promise(() => ok(accept_one(listener)))
	var client = connect(address, timeout: 2.seconds()).wait()?
	expect_equal(a.wait()?, 1)?
	client.close()?
}

// Accepts one connection and reads from it, all inside the promise that owns the
// connection.
fn accept_and_read(listener Listener) Int {
	var conn = listener.accept(2.seconds()).wait().get()
	r := within(conn.input, 2.seconds())
	if r.is_ok() and (r.get() != null) { return 1 }

	return 0
}

test "a promise reads a connection it owns" {
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	a := promise(() => ok(accept_and_read(listener)))
	var client = connect(address, timeout: 2.seconds()).wait()?
	client.output.write("xy".to_bytes())?
	client.output.flush()?
	expect_equal(a.wait()?, 1)?
	client.close()?
}

// Answers one DNS query with a single MX record: preference 10, exchange
// mail.example.test.
fn answer_mx(var served DatagramSocket) Int! {
	query := (
		(within(served.input, 2.seconds())?)
		or panic("called Optional.get() on null")
	)
	question := (query.data.slice(12, query.data.length())).get_or(Bytes([]))
	header := Bytes(
		[query.data.get(0), query.data.get(1), 129, 128, 0, 1, 0, 1, 0, 0, 0, 0]
	)
	record := Bytes([192, 12, 0, 15, 0, 1, 0, 0, 0, 0, 0, 21, 0, 10])
	name := Bytes(
		[
			4, 109, 97, 105, 108, 7, 101, 120, 97, 109, 112, 108, 101, 4, 116, 101, 115,
			116, 0
		]
	)
	served.output.write(
		Datagram(
			header.concat(question).concat(record).concat(name),
			query.address.clone(),
		)
	)?
	served.output.flush()?
	return ok(1)
}

test "resolve returns typed DNS records from the configured resolver" {
	one := resolve_dns("127.0.0.1", DnsKind.A, DnsOptions(timeout: 2.seconds()))?
	expect_equal(one.length(), 1)?
	expect_equal(one[0].value, "127.0.0.1")?
	expect_equal(one[0].kind.to_string(), "A")?

	server := bind_datagram("127.0.0.1:0")?
	derived := with_resolver(server.address.clone())?
	asking := promise(
		() => derived.resolve_dns(
			"example.test",
			DnsKind.MX,
			DnsOptions(timeout: 2.seconds()),
		)
	)
	var answering = server
	answered := answer_mx(answering)?
	mx := asking.wait()?
	expect_equal(mx.length(), 1)?
	expect_equal(mx[0].kind.to_string(), "MX")?
	expect_equal(mx[0].priority, 10)?
	expect_equal(mx[0].value, "mail.example.test.")?
	expect_equal(answered, 1)?
}

test "an empty host listens on every interface, with or without IPv6" {
	var listener = listen(":0")?
	parts := listener.address().split(":")
	port := parts[parts.length() - 1]
	var client = connect(f"127.0.0.1:{port}", timeout: 2.seconds()).wait()?
	var server = listener.accept(2.seconds()).wait()?
	client.output.write("hi".to_bytes())?
	client.output.flush()?
	expect_equal(
		(within(server.input, 2.seconds())?) or panic(
			"called Optional.get() on null"
		),
		"hi".to_bytes(),
	)?
	listener.close()?

	socket := bind_datagram(":0")?
	expect_false(socket.address.is_empty())?
}
// expect-exit: 0
// expect-tests: passed=14 failed=0
