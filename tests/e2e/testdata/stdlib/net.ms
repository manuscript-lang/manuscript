import {network, parse_ip, parse_cidr, contains_ip, NetworkError, IpFamily} from "@std/net.ms"
import panic from "@std/faults.ms"
import expect_error from "@std/testing.ms"

test "IP parsing CIDR normalization and containment":
    if (try parse_ip("2001:0db8::1")).text() != "2001:db8::1": return panic(
        "IPv6 normalization"
    )
    if (try parse_cidr("192.0.2.3/24")).text() != "192.0.2.0/24": return panic(
        "CIDR mask"
    )
    if not (
        try contains_ip(
            try parse_cidr("192.0.2.0/24"),
            try parse_ip("192.0.2.255")
        )
    ): return panic("CIDR membership")
    if (try contains_ip(try parse_cidr("192.0.2.0/24"), try parse_ip("192.0.3.0"))): return panic(
        "CIDR exclusion"
    )

    try expect_ip_error("999.1.1.1")

test "TCP loopback writes reads half close and EOF":
    let net = network()

    with listener = try net.listen("127.0.0.1:0"):
        with client = try net.connect(listener.address(), 2.seconds):
            with server = try listener.accept(2.seconds):
                try client.write("hello".to_bytes(), 2.seconds)
                if ((try server.read(5, 2.seconds)).get() != "hello".to_bytes()): return panic(
                    "TCP bytes"
                )
                if server.peer_address() != client.local_address(): return panic(
                    "TCP address"
                )

                try client.shutdown_write()
                if not (try server.read(5, 2.seconds)).is_none(): return panic(
                    "TCP EOF"
                )

test "UDP loopback preserves datagram data and sender":
    let net = network()

    with receiver = try net.bind_datagram("127.0.0.1:0"):
        with sender = try net.bind_datagram("127.0.0.1:0"):
            try sender.send("packet".to_bytes(), receiver.address(), 2.seconds)
            let packet = try receiver.receive(64, 2.seconds)
            if packet.data != "packet".to_bytes() or packet.sender != sender.address(): return panic(
                "UDP datagram"
            )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = try network().restrict([], [], allow_listen: false)
    with scoped = restricted:
        if (
            (
                try expect_error(restricted.listen("127.0.0.1:0"))
            ) != NetworkError.PermissionDenied
        ): return panic("listen denial identity")
    if (
        (
            try expect_error(restricted.connect("127.0.0.1:1", 1.seconds))
        ) != NetworkError.Closed
    ): return panic("network close identity")

test "typed addresses preserve normalization and reject zones":
    let ip = try parse_ip("::ffff:192.0.2.1")
    if ip.text() != "192.0.2.1" or ip.family() != IpFamily.IPv4: return panic(
        "mapped normalization"
    )
    if (try parse_ip("2001:db8::1")).family() != IpFamily.IPv6: return panic(
        "IPv6 family"
    )

    try expect_ip_error("fe80::1%eth0")
    if (try contains_ip(try parse_cidr("::ffff:192.0.2.0/120"), ip)): return panic(
        "normalized IPv4 matched mapped IPv6 prefix"
    )

fn expect_ip_error(input: String) Result[Unit, Error]:
    if (try expect_error(parse_ip(input))) != NetworkError.InvalidData: return panic(
        "wrong address error"
    )

    return ok(unit)
