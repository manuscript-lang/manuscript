import expect_equal, expect_error, expect_false from "@std/test.ms"
import Bytes from "@std/bytes.ms"
import (
    network,
    parse_ip,
    parse_cidr,
    contains_ip,
    DatagramSocket,
    DnsKind,
    NetworkError,
    IpFamily,
    Listener,
    Connection
) from "@std/net.ms"
import Shared, share from "@std/shared.ms"
import TaskGroup from "@std/tasks.ms"
import sleep from "@std/time.ms"

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
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    let client = try net.connect(listener.address(), 2.seconds)
    let server = try listener.accept(2.seconds)
    try client.write("hello", 2.seconds)
    try expect_equal((try server.read(5, 2.seconds)).get(), "hello".to_bytes())
    try expect_equal(server.peer_address(), client.local_address())
    try client.shutdown_write()
    try expect_false(not (try server.read(5, 2.seconds)).is_none())

test "UDP loopback preserves datagram data and sender":
    let net = network()
    let receiver = try net.bind_datagram("127.0.0.1:0")
    let sender = try net.bind_datagram("127.0.0.1:0")
    try sender.send("packet", receiver.address(), 2.seconds)

    let packet = try receiver.receive(64, 2.seconds)
    try expect_false(
        (
            packet.data != "packet".to_bytes()
            or packet.sender != sender.address()
        )
    )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = try network().restrict([], [], allow_listen: false)
    var closing = try network().restrict([], [], allow_listen: false)
    var scoped = restricted
    try expect_false(
        (
            (
                try expect_error(scoped.listen("127.0.0.1:0"))
            ) != NetworkError.PermissionDenied
        )
    )
    scoped.close()
    closing.close()
    try expect_false(
        (
            (
                try expect_error(
                    closing.connect("127.0.0.1:1", 1.seconds)
                )
            ) != NetworkError.Closed
        )
    )

test "typed addresses preserve normalization and reject zones":
    let ip = try parse_ip("::ffff:192.0.2.1")
    try expect_false(ip.text() != "192.0.2.1" or ip.family() != IpFamily.IPv4)
    try expect_equal((try parse_ip("2001:db8::1")).family(), IpFamily.IPv6)
    try expect_ip_error("fe80::1%eth0")
    try expect_false((try contains_ip(try parse_cidr("::ffff:192.0.2.0/120"), ip)))

fn expect_ip_error(input: String) Unit!:
    try expect_equal((try expect_error(parse_ip(input))), NetworkError.InvalidData)
    return ok(unit)

fn accept_one(l: Shared[Listener]) Int:
    let r = l.get().accept(2.seconds)

    if r.is_ok():
        r.get().close().get(none)
        return 1

    return 0

test "two tasks accept on one listener":
    let net = network()
    let shared: Shared[Listener] = share(try net.listen("127.0.0.1:0"))
    var group = TaskGroup[Int]()
    let a = shared
    let b = shared
    group.spawn(fn ch: accept_one(a))
    group.spawn(fn ch: accept_one(b))
    sleep(50.milliseconds)

    var c1 = try net.connect(shared.get().address(), 2.seconds)
    var c2 = try net.connect(shared.get().address(), 2.seconds)
    let got = try group.results()
    try expect_equal(got.length(), 2)
    try expect_equal(got[0] + got[1], 2)
    try c1.close()
    try c2.close()
    try group.close()
    try shared.get().close()

fn read_some(c: Shared[Connection]) Int:
    let r = c.get().read(1, 2.seconds)
    if r.is_ok() and r.get().is_some():
        return 1

    return 0

test "two tasks read one connection":
    let net = network()
    let listener = try net.listen("127.0.0.1:0")
    var client = try net.connect(listener.address(), 2.seconds)
    let server = try listener.accept(2.seconds)
    let shared: Shared[Connection] = share(server)
    var group = TaskGroup[Int]()
    let a = shared
    let b = shared
    group.spawn(fn ch: read_some(a))
    group.spawn(fn ch: read_some(b))
    sleep(50.milliseconds)
    try client.write("xy", 2.seconds)

    let got = try group.results()
    try expect_equal(got[0] + got[1], 2)
    try group.close()
    try client.close()
    try shared.get().close()

# Answers one DNS query with a single MX record: preference 10, exchange mail.example.test.
fn answer_mx(socket: Shared[DatagramSocket]) Int!NetworkError:
    let query = try socket.get().receive(512, 2.seconds)
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
    try socket.get().send_bytes(
        header.concat(question).concat(record).concat(name), query.sender, 2.seconds
    )
    return ok(1)

test "resolve returns typed DNS records from the configured resolver":
    let net = network()
    let one = try net.resolve("127.0.0.1", DnsKind.A, none, 2.seconds)
    try expect_equal(one.length(), 1)
    try expect_equal(one[0].value, "127.0.0.1")
    try expect_equal(one[0].kind.text(), "A")

    let server: Shared[DatagramSocket] = share(try net.bind_datagram("127.0.0.1:0"))
    let derived = try net.with_resolver(server.get().address())
    let group = TaskGroup[Int]()
    let socket = server
    group.spawn(fn ch: answer_mx(socket).get(0))

    let mx = try derived.resolve("example.test", DnsKind.MX, none, 2.seconds)
    try expect_equal(mx.length(), 1)
    try expect_equal(mx[0].kind.text(), "MX")
    try expect_equal(mx[0].priority, 10)
    try expect_equal(mx[0].value, "mail.example.test.")

    let answered = try group.results()
    try expect_equal(answered[0], 1)

test "an empty host listens on every interface, with or without IPv6":
    let net = network()
    var listener = try net.listen(":0")
    let parts = listener.address().split(":")
    let port = parts[parts.length() - 1]
    let client = try net.connect("127.0.0.1:{port}", 2.seconds)
    let server = try listener.accept(2.seconds)
    try client.write("hi", 2.seconds)
    try expect_equal((try server.read(2, 2.seconds)).get(), "hi".to_bytes())
    try listener.close()

    let socket = try net.bind_datagram(":0")
    try expect_false(socket.address().is_empty())
