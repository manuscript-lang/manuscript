import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import TextError from "@std/errors.ms"
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

test "IP parsing CIDR normalization and containment":
    (parse_ip("2001:0db8::1") | try expect_ok).text() | try expect_equal(
        expected: "2001:db8::1"
    )
    (parse_cidr("192.0.2.3/24") | try expect_ok).text() | try expect_equal(
        expected: "192.0.2.0/24"
    )
    try expect_false(
        not (
            contains_ip(
                cidr: (parse_cidr("192.0.2.0/24") | try expect_ok),
                address: (parse_ip("192.0.2.255") | try expect_ok)
            ) | try expect_ok
        )
    )
    try expect_false(
        (
            contains_ip(
                cidr: (parse_cidr("192.0.2.0/24") | try expect_ok),
                address: (parse_ip("192.0.3.0") | try expect_ok)
            ) | try expect_ok
        )
    )
    ("999.1.1.1" | try expect_ip_error)

test "TCP loopback writes reads half close and EOF":
    let net = network()

    with listener = (net.listen("127.0.0.1:0") | try expect_ok):
        with client = (
            net.connect(
                address: listener.address(),
                timeout: 2.seconds
            ) | try expect_ok
        ):
            with server = (listener.accept(timeout: 2.seconds) | try expect_ok):
                let sent = (
                    client.write(
                        data: "hello".to_bytes(),
                        timeout: 2.seconds
                    ) | try expect_ok
                )
                try expect_false(
                    (
                        (
                            server.read(
                                max_bytes: 5,
                                timeout: 2.seconds
                            ) | try expect_ok
                        ).unwrap() != "hello".to_bytes()
                    )
                )
                server.peer_address() | try expect_equal(
                    expected: client.local_address()
                )
                let shutdown = (client.shutdown_write() | try expect_ok)
                try expect_false(
                    not (
                        server.read(
                            max_bytes: 5,
                            timeout: 2.seconds
                        ) | try expect_ok
                    ).is_none()
                )

test "UDP loopback preserves datagram data and sender":
    let net = network()

    with receiver = (net.bind_datagram("127.0.0.1:0") | try expect_ok):
        with sender = (net.bind_datagram("127.0.0.1:0") | try expect_ok):
            let sent = (
                sender.send(
                    data: "packet".to_bytes(),
                    address: receiver.address(),
                    timeout: 2.seconds
                ) | try expect_ok
            )
            let packet = (
                receiver.receive(
                    max_bytes: 64,
                    timeout: 2.seconds
                ) | try expect_ok
            )
            try expect_false(
                (
                    packet.data != "packet".to_bytes()
                    or packet.sender != sender.address()
                )
            )

test "network restriction denies admission and close rejects acquisitions":
    let restricted = (
        network().restrict(
            hosts: [],
            cidrs: [],
            allow_listen: false
        ) | try expect_ok
    )

    with scoped = restricted:
        match restricted.listen("127.0.0.1:0"):
            ok(_): return fail("listen permission ignored")
            error(cause):
                try expect_equal(cause, NetworkError.PermissionDenied)

    match restricted.connect(address: "127.0.0.1:1", timeout: 1.seconds):
        ok(_): return fail("closed network admitted connection")
        error(cause):
            try expect_equal(cause, NetworkError.Closed)

test "typed addresses preserve normalization and reject zones":
    let ip = (parse_ip("::ffff:192.0.2.1") | try expect_ok)
    (ip.text() != "192.0.2.1" or ip.family() != IpFamily.IPv4) | try expect_false
    (parse_ip("2001:db8::1") | try expect_ok).family() | try expect_equal(
        expected: IpFamily.IPv6
    )
    ("fe80::1%eth0" | try expect_ip_error)
    try expect_false(
        (
            contains_ip(
                (parse_cidr("::ffff:192.0.2.0/120") | try expect_ok),
                ip
            ) | try expect_ok
        )
    )

fn expect_ip_error(input: String) -> Result[Unit, Error]:
    match parse_ip(input):
        ok(_): return error(TextError.Text("invalid IP accepted"))
        error(cause):
            if cause != NetworkError.InvalidData: return error(
                TextError.Text("wrong address error")
            )

    return ok(unit)
