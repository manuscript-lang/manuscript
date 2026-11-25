// conform: tags=faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: entry ranges stop at a function that is also used as a value
import stdout from "@std/io/io.ms"
import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn scale(chunk Int) Int! {
	var h = 0

	for i in 0..1000 {
		h = (h + chunk * 7919 + i) % 1000000007
	}

	return ok(h)
}

fn start(chunk Int) Promise[Int] {
	return promise[Int](() => scale(chunk))
}

fn apply(f fn(Int) Int!, n Int) Int {
	return f(n).get()
}

fn main() Void {
	var ps List[Promise[Int]] = []

	for chunk in 0..128 {
		ps.append(start(chunk))
	}

	var total = 0

	for r in wait_all(ps).get() {
		total += r
	}

	void stdout().write(f"{total}\n")
	void stdout().write(f"{apply(scale, 5)}\n")
	void stdout().write(f"{apply(scale, 4611686018427387904)}\n")
}
