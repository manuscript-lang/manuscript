from "@std/testing.ms" import expect_equal, expect_error, expect_false
from "@std/net.ms" import network, parse_ip, parse_cidr, contains_ip, NetworkError, IpFamily

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
