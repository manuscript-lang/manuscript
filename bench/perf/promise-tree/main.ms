import (
	Promise, promise, wait_all from "@std/concurrency/promise.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn fib(n: Int) Int:
	if n < 2: return n
	return fib(n - 1) + fib(n - 2)

// promise-per-level fib: spawn one half as a promise, compute other inline
fn pfib(n: Int, cutoff: Int) Int!:
	if n < cutoff: return ok(fib(n))

	m := n - 1
	p := promise[Int](fn: pfib(m, cutoff))
	b := try pfib(n - 2, cutoff)
	a := try p.wait()
	return ok(a + b)

fn work(n: Int) Int!:
	return ok(fib(n))

fn main() Unit:
	args := arguments()
	mode := args[0].clone()
	n := args[1].parse_int().get()
	k := args[2].parse_int().get()
	t0 := monotonic()
	var r = 0

	if mode == "fan":
		var ps: List[Promise[Int]] = []
		for i in 0..k:
			ps.append(promise[Int](fn: work(n)))

		rs := wait_all(ps).get()
		for x in rs:
			r += x
	else if mode == "tree":
		r = pfib(n, k).get()

	print(
		mode + " result " + r.to_string() + " ms " + (
			monotonic().difference(t0).to_nanoseconds()
			/ 1000000
		).to_string()
	)
