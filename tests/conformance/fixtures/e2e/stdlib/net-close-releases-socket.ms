// conform: tags=scope-cleanup,stdlib-net,tier-io
// conform: phase=run
import (
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	bind_datagram, connect, listen from "@std/net/net.ms",
	nanoseconds from "@std/time.ms",
)

// `close` frees the socket, so its port can be bound again while the handle is still held and
// after a cancelled `accept` or `read` ran its `with` cleanup.

fn accept_one(address: String) Int:
	listener := listen(address).get()
	accepted := listener.accept(nanoseconds(10000000000)).wait()
	if accepted.is_ok(): return 1

	return 0

fn read_one(address: String) Int:
	var client = connect(address, timeout: nanoseconds(2000000000)).wait().get()
	got := client.input.next()

	match got:
		ok(chunk):
			if chunk != null: return chunk.length()
			return -1
		error(_): return -1

fn receive_one(address: String) Int:
	var socket = bind_datagram(address).get()
	got := socket.input.next()
	if got.is_ok(): return 1

	return 0

fn rebound_datagram(address: String) Int:
	match bind_datagram(address):
		ok(bound):
			var again = bound
			void again.close()
			return 1
		error(_): return 0

fn rebound(address: String) Int:
	match listen(address):
		ok(bound):
			var again = bound
			void again.close()
			return 1
		error(_): return 0

fn cancel_accept(address: String) Void:
	work := promise(fn: ok(accept_one(address.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn cancel_read(address: String) Void:
	work := promise(fn: ok(read_one(address.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn cancel_receive(address: String) Void:
	work := promise(fn: ok(receive_one(address.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(2000000))).wait()

fn cancel_receive_within(address: String, ns: Int) Void:
	work := promise(fn: ok(receive_one(address.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(ns))).wait()

fn cancel_accept_within(address: String, ns: Int) Void:
	work := promise(fn: ok(accept_one(address.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(ns))).wait()

// A limit short enough to pass while the work is still binding: the wait returns only
// once the socket the work bound is closed, so the address binds again every time.
fn rebinds_lost_to_early_cancels(address: String) Int:
	var lost = 0

	for round in 0..300:
		cancel_receive_within(address.clone(), 1000 + round * 300)
		if rebound_datagram(address.clone()) == 0: lost += 1
		cancel_accept_within(address.clone(), 1000 + round * 300)
		if rebound(address.clone()) == 0: lost += 1

	return lost

fn main() Void:
	var first = listen("127.0.0.1:0").get()
	address := first.address().clone()
	void first.close()
	print(f"closed listener rebound: {rebound(address.clone())}")
	cancel_accept(address.clone())
	print(f"cancelled accept rebound: {rebound(address.clone())}")

	third := listen("127.0.0.1:0").get()
	third_address := third.address().clone()
	var server = third
	target := server.address().clone()

	for round in 0..20:
		cancel_read(target.clone())

		accepted := server.accept(nanoseconds(500000000)).wait()
		if connection := accepted:
			void connection.close()

	void server.close()
	print(f"cancelled reads rebound: {rebound(third_address.clone())}")

	var udp = bind_datagram("127.0.0.1:0").get()
	udp_address := udp.address.clone()
	void udp.close()
	(
		stdout().write(
			f"closed datagram socket rebound: {rebound_datagram(udp_address.clone())}\n"
		).get()
	)
	cancel_receive(udp_address.clone())
	(
		stdout().write(
			f"cancelled receive rebound: {rebound_datagram(udp_address.clone())}\n"
		).get()
	)
	(
		stdout()
		.write(
			f"rebinds lost to a cancel during the bind: {rebinds_lost_to_early_cancels(udp_address.clone())}\n"
		)
		.get()
	)
