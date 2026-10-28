# conform: tags=scope-cleanup,stdlib-net,tier-io
# conform: phase=run
from "@std/io.ms" import stdout
from "@std/net.ms" import network
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds

# `close` frees the socket, so its port can be bound again while the handle is still held and
# after a cancelled `accept` or `read` ran its `with` cleanup.

def accept_one(address: String) -> Int:
    let listener = network().listen(address).get()
    let accepted = listener.accept(nanoseconds(10000000000))
    if accepted.is_ok():
        return 1

    return 0

def read_one(address: String) -> Int:
    let client = network().connect(address, nanoseconds(2000000000)).get()
    let got = client.read(none, none)
    return got.get(none).map(lambda b: b.length()).get(-1)

def receive_one(address: String) -> Int:
    let socket = network().bind_datagram(address).get()
    let got = socket.receive(none, none)
    if got.is_ok():
        return 1

    return 0

def rebound_datagram(address: String) -> Int:
    match network().bind_datagram(address):
        case ok(bound):
            var again = bound
            again.close()
            return 1
        case error(_): return 0

def rebound(address: String) -> Int:
    match network().listen(address):
        case ok(bound):
            var again = bound
            again.close()
            return 1
        case error(_): return 0

export def main() -> Int:
    let net = network()
    var first = net.listen("127.0.0.1:0").get()
    let address = first.address().clone()
    first.close()
    stdout().write(f"closed listener rebound: {rebound(address)}\n").get()

    var group = TaskGroup[Int](timeout: some(nanoseconds(2000000)))
    let a = address.clone()
    group.spawn(lambda ch: accept_one(a))

    let _ = group.wait()
    group.close()
    stdout().write(f"cancelled accept rebound: {rebound(address)}\n").get()

    let third = net.listen("127.0.0.1:0").get()
    let third_address = third.address().clone()
    var server = third
    let target = server.address().clone()

    for round in 0..20:
        let round_a = target.clone()
        var round_group = TaskGroup[Int](timeout: some(nanoseconds(2000000)))
        round_group.spawn(lambda ch: read_one(round_a))

        let _ = round_group.wait()
        round_group.close()

        let accepted = server.accept(nanoseconds(500000000))
        if accepted.is_ok():
            accepted.get().close()

    server.close()
    stdout().write(f"cancelled reads rebound: {rebound(third_address)}\n").get()

    var udp = net.bind_datagram("127.0.0.1:0").get()
    let udp_address = udp.address().clone()
    udp.close()
    (
        stdout().write(
            f"closed datagram socket rebound: {rebound_datagram(udp_address)}\n"
        ).get()
    )

    var group2 = TaskGroup[Int](timeout: some(nanoseconds(2000000)))
    let datagram_a = udp_address.clone()
    group2.spawn(lambda ch: receive_one(datagram_a))

    let _ = group2.wait()
    group2.close()
    (
        stdout().write(
            f"cancelled receive rebound: {rebound_datagram(udp_address)}\n"
        ).get()
    )
    return 0
