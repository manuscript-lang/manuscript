import promise, wait_all from "@std/concurrency/promise.ms"

fn fib(n Int) Int {
	return if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

fn main() Void {
	tasks := [36, 36, 36, 36].map(n => promise(() => ok(fib(n))))
	print(wait_all(tasks).get_or(List[Int]()).length())
}
