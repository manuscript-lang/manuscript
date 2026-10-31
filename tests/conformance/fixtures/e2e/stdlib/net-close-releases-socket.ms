# conform: tags=scope-cleanup,stdlib-net,tier-io
# conform: phase=run
import stdout from "@std/io.ms"
import bind_datagram, connect, listen from "@std/net.ms"
import TaskGroup from "@std/tasks.ms"
import nanoseconds from "@std/time.ms"

# `close` frees the socket, so its port can be bound again while the handle is still held and
# after a cancelled `accept` or `read` ran its `with` cleanup.

fn accept_one(address: String) Int:
    let listener = listen(address).get()
    let accepted = listener.accept(nanoseconds(10000000000))
    if accepted.is_ok():
        return 1

    return 0

fn read_one(address: String) Int:
    let client = connect(address, nanoseconds(2000000000)).get()
    let got = client.read(none, none)
    return got.get(none).map(fn b: b.length()).get(-1)

fn receive_one(address: String) Int:
    let socket = bind_datagram(address).get()
    let got = socket.receive(none, none)
    if got.is_ok():
        return 1

    return 0

fn rebound_datagram(address: String) Int:
    match bind_datagram(address):
        ok(bound):
            var again = bound
            again.close().get(none)
            return 1
        error(_): return 0

fn rebound(address: String) Int:
    match listen(address):
        ok(bound):
            var again = bound
            again.close().get(none)
            return 1
        error(_): return 0

export fn main() Int:
    var first = listen("127.0.0.1:0").get()
    let address = first.address().clone()
    first.close().get(none)
    stdout().write("closed listener rebound: {rebound(address)}\n").get()

    var group = TaskGroup[Int](timeout: nanoseconds(2000000))
    let a = address.clone()
    group.spawn(fn ch: accept_one(a))

    let _ = group.wait()
    group.close().get(none)
    stdout().write("cancelled accept rebound: {rebound(address)}\n").get()

    let third = listen("127.0.0.1:0").get()
    let third_address = third.address().clone()
    var server = third
    let target = server.address().clone()

    for round in 0..20:
        let round_a = target.clone()
        var round_group = TaskGroup[Int](timeout: nanoseconds(2000000))
        round_group.spawn(fn ch: read_one(round_a))

        let _ = round_group.wait()
        round_group.close().get(none)

        let accepted = server.accept(nanoseconds(500000000))
        if accepted.is_ok():
            accepted.get().close().get(none)

    server.close().get(none)
    stdout().write("cancelled reads rebound: {rebound(third_address)}\n").get()

    var udp = bind_datagram("127.0.0.1:0").get()
    let udp_address = udp.address().clone()
    udp.close().get(none)
    (
        stdout().write(
            "closed datagram socket rebound: {rebound_datagram(udp_address)}\n"
        ).get()
    )

    var group2 = TaskGroup[Int](timeout: nanoseconds(2000000))
    let datagram_a = udp_address.clone()
    group2.spawn(fn ch: receive_one(datagram_a))

    let _ = group2.wait()
    group2.close().get(none)
    stdout().write("cancelled receive rebound: {rebound_datagram(udp_address)}\n").get()
    return 0
