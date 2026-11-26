// conform: tags=perf,tier-core
// conform: phase=run
// conform: origin=range pass: entry ranges through a promise capture
import stdout from "@std/io/io.ms"
import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn scale(chunk Int) Int! {
	var x = chunk * 7919 + 1
	var hist List[Int] = []

	for b in 0..16 {
		hist.append(0)
	}

	for i in 0..1000 {
		x = (x * 48271) % 2147483647
		hist[x % 16] = hist[x % 16] + 1
	}

	return ok(hist[3] * 1000 + x % 1000)
}

fn start(chunk Int) Promise[Int] {
	return promise[Int](() => scale(chunk))
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
}
// expect-exit: 0
// expect-stdout: 8145580
