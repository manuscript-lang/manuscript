// Concurrency: CPU-bound work fanned out over promises, then many small promises.
// Compared with threads, goroutines and worker threads.
import Promise, promise, wait_all from "@std/concurrency/promise.ms"

fn count_primes(lo: Int, hi: Int) Int!:
	var count = 0

	for n in lo..hi:
		if n < 2: continue

		var is_prime = true
		var d = 2

		while d * d <= n:
			if n % d == 0:
				is_prime = false
				break

			d += 1

		if is_prime: count += 1

	return ok(count)

fn small(i: Int) Int!:
	var t = 0
	for k in 0..200:
		t += (i + k) % 7
	return ok(t)

// A promise a function returns owns the values it captured.
fn start_primes(lo: Int) Promise[Int]:
	return promise[Int](fn: count_primes(lo, lo + 250000))

fn start_small(i: Int) Promise[Int]:
	return promise[Int](fn: small(i))

fn main() Unit:
	var ps: List[Promise[Int]] = []
	for chunk in 0..16:
		ps.append(start_primes(chunk * 250000))

	var primes = 0
	for r in wait_all(ps).get():
		primes += r

	var many: List[Promise[Int]] = []
	for i in 0..100000:
		many.append(start_small(i))

	var total = 0
	for r in wait_all(many).get():
		total += r
	print("primes {primes} small {total}")
