import {
    network,
    parse_ip,
    parse_cidr,
    contains_ip,
    NetworkError,
    Connection,
    IpAddress,
    IpFamily
} from "@std/net.ms"
import IoError from "@std/io.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "IP parsing CIDR normalization and containment":
    if value(parse_ip("2001:0db8::1")).text() != "2001:db8::1": return panic(
        "IPv6 normalization"
    )
    if value(parse_cidr("192.0.2.3/24")).text() != "192.0.2.0/24": return panic(
        "CIDR mask"
    )
    if not value(
        contains_ip(
            cidr: value(parse_cidr("192.0.2.0/24")),
            address: value(parse_ip("192.0.2.255"))
        )
    ): return panic("CIDR membership")
    if value(
        contains_ip(
            cidr: value(parse_cidr("192.0.2.0/24")),
            address: value(parse_ip("192.0.3.0"))
        )
    ): return panic("CIDR exclusion")

    expect_ip_error("999.1.1.1")

test "TCP loopback writes reads half close and EOF":
    let net = network()

    with listener = value(net.listen("127.0.0.1:0")):
        with client = value(
            net.connect(address: listener.address(), timeout: 2.seconds)
        ):
            with server = value(listener.accept(timeout: 2.seconds)):
                let sent = value(
                    client.write(
                        data: "hello".to_bytes(),
                        timeout: 2.seconds
                    )
                )
                if (
                    value(
                        server.read(
                            max_bytes: 5,
                            timeout: 2.seconds
                        )
                    ).unwrap() != "hello".to_bytes()
                ): return panic("TCP bytes")
                if server.peer_address() != client.local_address(): return panic(
                    "TCP address"
                )

                let shutdown = value(client.shutdown_write())
                if not value(server.read(max_bytes: 5, timeout: 2.seconds)).is_none(): return panic(
                    "TCP EOF"
                )

test "UDP loopback preserves datagram data and sender":
    let net = network()

    with receiver = value(net.bind_datagram("127.0.0.1:0")):
        with sender = value(net.bind_datagram("127.0.0.1:0")):
            let sent = value(
                sender.send(
                    data: "packet".to_bytes(),
                    address: receiver.address(),
                    timeout: 2.seconds
                )
            )
            let packet = value(receiver.receive(max_bytes: 64, timeout: 2.seconds))
            if packet.data != "packet".to_bytes() or packet.sender != sender.address(): return panic(
                "UDP datagram"
            )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = value(
        network().restrict(hosts: [], cidrs: [], allow_listen: false)
    )

    with scoped = restricted:
        match restricted.listen("127.0.0.1:0"):
            ok(_): return panic("listen permission ignored")

            error(cause):
                if cause != NetworkError.PermissionDenied: return panic(
                    "listen denial identity"
                )

    match restricted.connect(address: "127.0.0.1:1", timeout: 1.seconds):
        ok(_): return panic("closed network admitted connection")

        error(cause):
            if cause != NetworkError.Closed: return panic("network close identity")

test "typed addresses preserve normalization and reject zones":
    let ip = value(parse_ip("::ffff:192.0.2.1"))
    if ip.text() != "192.0.2.1" or ip.family() != IpFamily.IPv4: return panic(
        "mapped normalization"
    )
    if value(parse_ip("2001:db8::1")).family() != IpFamily.IPv6: return panic(
        "IPv6 family"
    )

    expect_ip_error("fe80::1%eth0")
    if value(contains_ip(value(parse_cidr("::ffff:192.0.2.0/120")), ip)): return panic(
        "normalized IPv4 matched mapped IPv6 prefix"
    )

fn expect_ip_error(input: String) -> Unit:
    match parse_ip(input):
        ok(_): return panic("invalid IP accepted")
        error(cause):
            if cause != NetworkError.InvalidData: return panic("wrong address error")
