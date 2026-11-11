// Scheduler mailbox traffic: starts short promise tasks from the main thread, `window`
// at a time, and waits for each batch. Every promise is a Start sent to a scheduler
// thread and an Ended event sent back, so the run is dominated by cross-thread mail and
// wake-ups. A small window keeps the stacks of finished tasks in the pool, so stack
// setup does not hide the mail cost.
// `ms run bench/perf/mailbox/main.ms -- 100000 5 [window]`: promises per round, rounds, window (default 64).
import (
	Promise, promise from "@std/concurrency/promise.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn work(a: Int) Int!:
	return ok(a * 2 + 1)

fn main() Unit:
	args := arguments()
	n := args[0].parse_int().get()
	rounds := args[1].parse_int().get()
	window := if args.length() > 2: args[2].parse_int().get() else: 64
	var total = 0
	t0 := monotonic()

	for r in 0..rounds:
		var done = 0

		while done < n:
			var promises: List[Promise[Int]] = []
			for i in 0..window:
				promises.append(promise[Int](fn: work(done + i)))
			for p in promises:
				total += p.wait().get()
			done += window

	t1 := monotonic()
	print("total " + total.to_string())
	print(
		"ns/promise " + (
			t1.difference(t0).to_nanoseconds()
			/ (n * rounds)
		).to_string()
	)
