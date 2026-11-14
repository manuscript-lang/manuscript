// 100k promises of about 1 us of work each, started in a list and awaited together (the
// small half of bench/perf/suite/workers).
// `MS_THREADS=4 ms run bench/perf/small-promises/main.ms`
import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn small(i: Int) Int!:
	var t = 0
	for k in 0..200:
		t += (i + k) % 7
	return ok(t)

fn start_small(i: Int) Promise[Int]:
	return promise[Int](fn: small(i))

fn main() Unit:
	var many: List[Promise[Int]] = []
	for i in 0..100000:
		many.append(start_small(i))

	var total = 0
	for r in wait_all(many).get():
		total += r
	print("small {total}")
