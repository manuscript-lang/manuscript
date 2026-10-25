from "@std/testing.ms" import expect_equal, expect_error, expect_false
from "@std/net.ms" import network, parse_ip, parse_cidr, contains_ip, NetworkError, IpFamily, Listener, Connection
from "@std/shared.ms" import Shared, share
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep

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

    with try net.listen("127.0.0.1:0") as listener:
        with try net.connect(listener.address(), 2.seconds) as client:
            with try listener.accept(2.seconds) as server:
                try client.write("hello", 2.seconds)
                try expect_equal(
                    (try server.read(5, 2.seconds)).get(), "hello".to_bytes()
                )
                try expect_equal(server.peer_address(), client.local_address())
                try client.shutdown_write()
                try expect_false(not (try server.read(5, 2.seconds)).is_none())

test "UDP loopback preserves datagram data and sender":
    let net = network()

    with try net.bind_datagram("127.0.0.1:0") as receiver:
        with try net.bind_datagram("127.0.0.1:0") as sender:
            try sender.send("packet", receiver.address(), 2.seconds)

            let packet = try receiver.receive(64, 2.seconds)
            try expect_false(
                (
                    packet.data != "packet".to_bytes()
                    or packet.sender != sender.address()
                )
            )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = try network().restrict([], [], allow_listen: False)
    var closing = try network().restrict([], [], allow_listen: False)
    with restricted as scoped:
        try expect_false(
            (
                (
                    try expect_error(scoped.listen("127.0.0.1:0"))
                ) != NetworkError.PermissionDenied
            )
        )
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

def expect_ip_error(input: String) -> Result[Unit, Error]:
    try expect_equal((try expect_error(parse_ip(input))), NetworkError.InvalidData)
    return ok(())

def accept_one(l: Shared[Listener]) -> Int:
    let r = l.get().accept(2.seconds)
    if r.is_ok():
        r.get().close()
        return 1
    return 0

test "two tasks accept on one listener":
    let net = network()
    let shared: Shared[Listener] = share(try net.listen("127.0.0.1:0"))
    with TaskGroup[Int]() as group:
        let a = shared
        let b = shared
        group.spawn(lambda ch: accept_one(a))
        group.spawn(lambda ch: accept_one(b))
        sleep(50.milliseconds)
        let c1 = try net.connect(shared.get().address(), 2.seconds)
        let c2 = try net.connect(shared.get().address(), 2.seconds)
        let got = try group.results()
        try expect_equal(got.length(), 2)
        try expect_equal(got[0] + got[1], 2)
        c1.close()
        c2.close()
    shared.get().close()

def read_some(c: Shared[Connection]) -> Int:
    let r = c.get().read(some(1), some(2.seconds))
    if r.is_ok() and r.get().is_some():
        return 1
    return 0

test "two tasks read one connection":
    let net = network()
    with try net.listen("127.0.0.1:0") as listener:
        let client = try net.connect(listener.address(), 2.seconds)
        let server = try listener.accept(2.seconds)
        let shared: Shared[Connection] = share(server)
        with TaskGroup[Int]() as group:
            let a = shared
            let b = shared
            group.spawn(lambda ch: read_some(a))
            group.spawn(lambda ch: read_some(b))
            sleep(50.milliseconds)
            try client.write("xy", 2.seconds)
            let got = try group.results()
            try expect_equal(got[0] + got[1], 2)
        client.close()
        shared.get().close()
