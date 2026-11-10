// conform: tags=scope-cleanup,stdlib-net,tier-io
// conform: phase=run
import stdout from "@std/io/io.ms"
import bind_datagram, connect, listen from "@std/net/net.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import nanoseconds from "@std/time.ms"

// `close` frees the socket, so its port can be bound again while the handle is still held and
// after a cancelled `accept` or `read` ran its `with` cleanup.

fn accept_one(address: String) Int:
    let listener = listen(address).get()
    let accepted = listener.accept(nanoseconds(10000000000)).wait()
    if accepted.is_ok():
        return 1

    return 0

fn read_one(address: String) Int:
    var client = connect(address, timeout: nanoseconds(2000000000)).wait().get()
    let got = client.input.next()
    return got.get(none).map(fn b: b.length()).get(-1)

fn receive_one(address: String) Int:
    var socket = bind_datagram(address).get()
    let got = socket.input.next()
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

fn cancel_accept(address: String) Unit:
    let work = promise(fn: ok(accept_one(address.clone())))
    let _ = work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn cancel_read(address: String) Unit:
    let work = promise(fn: ok(read_one(address.clone())))
    let _ = work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn cancel_receive(address: String) Unit:
    let work = promise(fn: ok(receive_one(address.clone())))
    let _ = work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn main() Unit:
    var first = listen("127.0.0.1:0").get()
    let address = first.address().clone()
    first.close().get(none)
    print("closed listener rebound: {rebound(address.clone())}")
    cancel_accept(address.clone())
    print("cancelled accept rebound: {rebound(address.clone())}")

    let third = listen("127.0.0.1:0").get()
    let third_address = third.address().clone()
    var server = third
    let target = server.address().clone()

    for round in 0..20:
        cancel_read(target.clone())

        let accepted = server.accept(nanoseconds(500000000)).wait()

        if accepted.is_ok():
            var connection = accepted.get(none)
            connection.close().get(none)

    server.close().get(none)
    print("cancelled reads rebound: {rebound(third_address.clone())}")

    var udp = bind_datagram("127.0.0.1:0").get()
    let udp_address = udp.address.clone()
    udp.close().get(none)
    (
        stdout().write(
            "closed datagram socket rebound: {rebound_datagram(udp_address.clone())}\n"
        ).get()
    )
    cancel_receive(udp_address.clone())
    (
        stdout().write(
            "cancelled receive rebound: {rebound_datagram(udp_address.clone())}\n"
        ).get()
    )
