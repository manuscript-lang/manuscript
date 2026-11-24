import (
	Promise, promise, wait_all from "@std/concurrency/promise.ms",
	panic from "@std/core.ms",
	stdout from "@std/io/io.ms",
	FetcherOptions, fetcher from "@std/net/fetch.ms",
	arguments from "@std/os/env.ms",
	monotonic, nanoseconds from "@std/time.ms",
)

fn worker(url String, nanos Int) Int {
	var f = fetcher(FetcherOptions(cookies: url.contains("/cookie"))).get()
	started := monotonic()
	var n = 0

	while monotonic().difference(started).compare(nanoseconds(nanos)) < 0 {
		if r := f.fetch(url).wait() {
			n += r.body.length()
			n -= r.body.length() - 1
		} else {
			return -1000000
		}
	}

	void f.close()
	return n
}

// Runs `conns` fetching promises; the runtime spreads them over its threads.
fn main() Void {
	args := arguments()
	url := args.get(0)
	conns := args.get(1).parse_int() or panic("called Optional.get() on null")
	secs := args.get(2).parse_int() or panic("called Optional.get() on null")
	var total = 0
	var running List[Promise[Int]] = []
	for i in 0..conns {
		running.append(promise(() => ok(worker(url.clone(), secs * 1000000000))))
	}
	for r in wait_all(running).get() {
		total += r
	}
	void stdout().write(f"req/s {total / secs}\n")
}
