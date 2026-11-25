// ms: allow_effect std.clock.read
// ms: allow_effect std.clock.sleep
// ms: allow_effect std.net.connect
// ms: allow_effect std.net.listen

// Cost of each async primitive, one mode per primitive. Prints `mode ns/op`.
// `ms build bench/perf/async-primitives/main.ms -o probe && ./probe <mode> <n>`.
//
//   inline    start a promise and wait for it at once (the waiter may run the work itself)
//   here      the same with Placement.Here: a task, two switches, a wake
//   batch     start 64 promises, then wait for each (the mailbox shape)
//   pingpong  a round trip over two pipes with a task on this thread: two wakes, two switches
//   stream    one writer task, one reader, capacity 64: hand-over under back pressure
//   sleep     a timer of zero: arm, expire, wake
//   echo      a 64-byte round trip over loopback TCP with the server task on this thread
import (
	Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Pipe, pipe from "@std/io/io.ms",
	Listener, connect, listen from "@std/net/net.ms",
	arguments from "@std/os/env.ms",
	monotonic, nanoseconds, sleep from "@std/time.ms",
)

fn work(a Int) Int! {
	return ok(a * 2 + 1)
}

fn run_inline(n Int) Int {
	var total = 0

	for i in 0..n {
		p := promise[Int](() => work(i))
		total += p.wait().get()
	}

	return total
}

fn run_here(n Int) Int {
	var total = 0

	for i in 0..n {
		p := promise[Int](
			() => work(i),
			options: PromiseOptions(placement: Placement.Here),
		)
		total += p.wait().get()
	}

	return total
}

fn run_batch(n Int, here Bool) Int {
	var total = 0
	var done = 0

	while done < n {
		var promises List[Promise[Int]] = []

		for i in 0..64 {
			value := done + i

			if here {
				promises.append(
					promise[Int](
						() => work(value),
						options: PromiseOptions(
							placement: Placement.Here
						),
					)
				)
			} else {
				promises.append(promise[Int](() => work(value)))
			}
		}

		for p in promises {
			total += p.wait().get()
		}
		done += 64
	}

	return total
}

fn echo_pipe(requests, replies Pipe[Int]) Void! {
	var out = replies.writer()

	while true {
		next := requests.receive()?

		if next != null {
			out.write(next + 1)?
		} else {
			return out.close()
		}
	}
}

fn run_pingpong(n Int) Int {
	requests := pipe[Int](1)
	replies := pipe[Int](1)
	var out = requests.writer()
	var gate = replies.writer()
	server := promise[Void](
		() => echo_pipe(requests, replies),
		options: PromiseOptions(placement: Placement.Here),
	)
	var total = 0

	for i in 0..n {
		out.write(i).get()

		value := replies.receive().get()
		if value != null { total += value }
	}

	out.close().get()
	gate.close().get()
	server.wait().get()
	return total
}

fn produce(values Pipe[Int], n Int) Void! {
	var out = values.writer()
	for i in 0..n {
		out.write(i)?
	}
	return out.close()
}

fn run_stream(n Int) Int {
	values := pipe[Int](64)

	// The gate keeps the pipe open until the producer has made its own writer.
	var gate = values.writer()
	writer := promise[Void](
		() => produce(values, n),
		options: PromiseOptions(placement: Placement.Here),
	)
	var total = 0

	for i in 0..n {
		value := values.receive().get()
		if value != null { total += value }
	}

	gate.close().get()
	writer.wait().get()
	return total
}

fn run_sleep(n Int) Int {
	for i in 0..n {
		sleep(nanoseconds(0)).wait().get()
	}
	return n
}

fn echo_tcp(var listener Listener) Void! {
	var conn = listener.accept().wait()?

	while true {
		chunk := conn.input.next()?

		if chunk != null {
			conn.output.write(chunk)?
			conn.output.flush()?
		} else {
			return conn.close()
		}
	}
}

fn run_echo(n Int) Int {
	var listener = listen("127.0.0.1:0").get()
	address := listener.address()
	server := promise[Void](
		() => echo_tcp(listener),
		options: PromiseOptions(placement: Placement.Here),
	)
	var client = connect(address).wait().get()
	var total = 0
	message := "0123456789012345678901234567890123456789012345678901234567890123".to_bytes()

	for i in 0..n {
		client.output.write(message.clone()).get()
		client.output.flush().get()

		data := client.input.next().get()
		if data != null { total += data.length() }
	}

	client.close().get()
	server.wait().get()
	return total
}

fn main() Void {
	args := arguments()
	mode := args[0].clone()
	n := args[1].parse_int() or 0
	before := monotonic()
	var total = 0

	if mode == "inline" {
		total = run_inline(n)
	} else if mode == "here" {
		total = run_here(n)
	} else if mode == "batch" {
		total = run_batch(n, false)
	} else if mode == "batch-here" {
		total = run_batch(n, true)
	} else if mode == "pingpong" {
		total = run_pingpong(n)
	} else if mode == "stream" {
		total = run_stream(n)
	} else if mode == "sleep" {
		total = run_sleep(n)
	} else if mode == "echo" {
		total = run_echo(n)
	}

	elapsed := monotonic().difference(before).to_nanoseconds()
	print(f"{mode} total {total} ns/op {elapsed / n}")
}
