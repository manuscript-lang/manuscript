import (
    expect_equal, expect_error, expect_false, expect_true from "@std/test/test.ms",
    Bytes from "@std/bytes.ms",
    within from "./support/conn.ms",
    DnsOptions,
    bind_datagram,
    connect,
    connect_unix,
    listen,
    listen_unix,
    resolve_dns,
    restrict,
    with_resolver,
    Datagram,
    DatagramSocket,
    Listener,
    Connection from "@std/net/net.ms",
    parse_ip, parse_cidr, contains_ip, DnsKind, IpFamily from "@std/net/ip.ms",
    promise from "@std/concurrency/promise.ms",
)

test "IP parsing CIDR normalization and containment":
    try expect_equal((try parse_ip("2001:0db8::1")).text(), "2001:db8::1")
    try expect_equal((try parse_cidr("192.0.2.3/24")).text(), "192.0.2.0/24")
    try expect_false(
        not (
            try contains_ip(
                try parse_cidr("192.0.2.0/24"), try parse_ip("192.0.2.255")
            )
        )
    )
    try expect_false(
        (
            try contains_ip(
                try parse_cidr("192.0.2.0/24"), try parse_ip("192.0.3.0")
            )
        )
    )
    try expect_ip_error("999.1.1.1")

test "TCP loopback writes reads half close and EOF":
    let listener = try listen("127.0.0.1:0")
    var client = try connect(listener.address(), timeout: 2.seconds()).wait()
    var server = try listener.accept(2.seconds()).wait()
    try client.output.write("hello".to_bytes())
    try client.output.flush()
    try expect_equal(
        (try within(var server.input, 2.seconds())).get(), "hello".to_bytes()
    )
    try expect_equal(server.info.peer_address, client.info.local_address)
    try client.output.close()
    try expect_true((try within(var server.input, 2.seconds())).is_none())

test "a read cancelled by its timeout leaves the stream closable":
    let listener = try listen("127.0.0.1:0")
    var client = try connect(listener.address(), timeout: 2.seconds()).wait()
    let _server = try listener.accept(2.seconds()).wait()

    // The peer is silent, so the limit cancels the read mid-park. The borrowed stream still
    // belongs to the caller: closing it afterwards frees the socket once.
    try expect_true(within(var client.input, 50.milliseconds()).is_error())
    try client.close()

fn accept_all(listener: Listener) Unit!:
    while true:
        let _connection = try listener.accept().wait()
    return ok(unit)

test "a promise that accepts on a listener runs where the listener lives":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    let _accepting = promise(fn: accept_all(listener))

    // Accepts and connects register their connections with one network, which is not thread
    // safe: running the accepts on another thread raced these connects and panicked.
    for i in 0..2000:
        var client = try connect(address, timeout: 2.seconds()).wait()
        try client.close()

test "closing the input leaves the output open and closing both ends the connection":
    let listener = try listen("127.0.0.1:0")
    var client = try connect(listener.address(), timeout: 2.seconds()).wait()
    var server = try listener.accept(2.seconds()).wait()

    // Closing only the input does not end the stream the peer reads.
    try client.input.close()
    try client.output.write("still open".to_bytes())
    try client.output.flush()
    try expect_equal(
        (try within(var server.input, 2.seconds())).get(), "still open".to_bytes()
    )

    // Closing the output too closes the socket: the peer sees the end of the stream.
    try client.output.close()
    try expect_true((try within(var server.input, 2.seconds())).is_none())

test "host names resolve whatever their case":
    let listener = try listen("127.0.0.1:0")
    let port = listener.address().split(":").last().get("")
    let client = try connect("LocalHost:{port}", timeout: 2.seconds()).wait()
    let server = try listener.accept(2.seconds()).wait()
    try expect_equal(server.info.peer_address, client.info.local_address)

test "an empty Unix socket path is invalid input":
    try expect_equal(
        try expect_error(listen_unix("")),
        Error("network: invalid input", kind: "EINVAL")
    )
    try expect_equal(
        try expect_error(connect_unix("", timeout: 1.seconds()).wait()),
        Error("network: invalid input", kind: "EINVAL")
    )

test "UDP loopback preserves datagram data and sender":
    var receiver = try bind_datagram("127.0.0.1:0")
    var sender = try bind_datagram("127.0.0.1:0")
    try sender.output.write(Datagram("packet".to_bytes(), receiver.address.clone()))

    let packet = (try within(var receiver.input, 2.seconds())).get()
    try expect_false(
        (packet.data != "packet".to_bytes() or packet.address != sender.address)
    )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = try restrict([], [], allow_listen: false)
    var closing = try restrict([], [], allow_listen: false)
    var scoped = restricted
    try expect_false(
        (
            (try expect_error(scoped.listen("127.0.0.1:0"))) != Error(
                "network: permission denied", kind: "EACCES"
            )
        )
    )
    scoped.close()
    closing.close()
    try expect_false(
        (
            (
                try expect_error(
                    closing.connect(
                        "127.0.0.1:1", timeout: 1.seconds()
                    )
                )
            ) != Error("network: resource is closed", kind: "EBADF")
        )
    )

test "typed addresses preserve normalization and reject zones":
    let ip = try parse_ip("::ffff:192.0.2.1")
    try expect_false(ip.text() != "192.0.2.1" or ip.family() != IpFamily.IPv4)
    try expect_equal((try parse_ip("2001:db8::1")).family(), IpFamily.IPv6)
    try expect_ip_error("fe80::1%eth0")
    try expect_false((try contains_ip(try parse_cidr("::ffff:192.0.2.0/120"), ip)))

fn expect_ip_error(input: String) Unit!:
    try expect_equal(
        (try expect_error(parse_ip(input))),
        Error("network: invalid data", kind: "EBADMSG")
    )
    return ok(unit)

fn accept_one(l: Listener) Int:
    let r = l.accept(2.seconds()).wait()

    if r.is_ok():
        r.get().close().get(none)
        return 1

    return 0

test "a promise accepts on a listener it owns":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    let a = promise(fn: ok(accept_one(listener)))
    var client = try connect(address, timeout: 2.seconds()).wait()
    try expect_equal(try a.wait(), 1)
    try client.close()

// Accepts one connection and reads from it, all inside the promise that owns the connection.
fn accept_and_read(listener: Listener) Int:
    var conn = listener.accept(2.seconds()).wait().get()
    let r = within(var conn.input, 2.seconds())
    if r.is_ok() and r.get().is_some(): return 1

    return 0

test "a promise reads a connection it owns":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    let a = promise(fn: ok(accept_and_read(listener)))
    var client = try connect(address, timeout: 2.seconds()).wait()
    try client.output.write("xy".to_bytes())
    try client.output.flush()
    try expect_equal(try a.wait(), 1)
    try client.close()

// Answers one DNS query with a single MX record: preference 10, exchange mail.example.test.
fn answer_mx(var served: DatagramSocket) Int!:
    let query = (try within(var served.input, 2.seconds())).get()
    let question = (query.data.slice(12, query.data.length())).get(Bytes([]))
    let header = Bytes(
        [query.data.get(0), query.data.get(1), 129, 128, 0, 1, 0, 1, 0, 0, 0, 0]
    )
    let record = Bytes([192, 12, 0, 15, 0, 1, 0, 0, 0, 0, 0, 21, 0, 10])
    let name = Bytes(
        [
            4, 109, 97, 105, 108, 7, 101, 120, 97, 109, 112, 108, 101, 4, 116, 101, 115,
            116, 0
        ]
    )
    try served.output.write(
        Datagram(
            header.concat(question).concat(record).concat(name), query.address
        )
    )
    try served.output.flush()
    return ok(1)

test "resolve returns typed DNS records from the configured resolver":
    let one = try resolve_dns("127.0.0.1", DnsKind.A, DnsOptions(timeout: 2.seconds()))
    try expect_equal(one.length(), 1)
    try expect_equal(one[0].value, "127.0.0.1")
    try expect_equal(one[0].kind.text(), "A")

    let server = try bind_datagram("127.0.0.1:0")
    let derived = try with_resolver(server.address.clone())
    let asking = promise(
        fn: derived.resolve(
            "example.test", DnsKind.MX, DnsOptions(timeout: 2.seconds())
        )
    )
    var answering = server
    let answered = try answer_mx(var answering)
    let mx = try asking.wait()
    try expect_equal(mx.length(), 1)
    try expect_equal(mx[0].kind.text(), "MX")
    try expect_equal(mx[0].priority, 10)
    try expect_equal(mx[0].value, "mail.example.test.")
    try expect_equal(answered, 1)

test "an empty host listens on every interface, with or without IPv6":
    var listener = try listen(":0")
    let parts = listener.address().split(":")
    let port = parts[parts.length() - 1]
    var client = try connect("127.0.0.1:{port}", timeout: 2.seconds()).wait()
    var server = try listener.accept(2.seconds()).wait()
    try client.output.write("hi".to_bytes())
    try client.output.flush()
    try expect_equal((try within(var server.input, 2.seconds())).get(), "hi".to_bytes())
    try listener.close()

    let socket = try bind_datagram(":0")
    try expect_false(socket.address.is_empty())
