import Promise, promise, wait_all from "@std/concurrency/promise.ms"

bench "promise.spawn_wait_all_1000" per 1000:
	var running List[Promise[Int]] = []
	for i in 0..1000:
		running.append(promise(fn: ok(i * 2)))

	r := wait_all(running).get_or([])
	r.length()

bench "promise.spawn_wait_each_1000" per 1000:
	var n = 0

	for i in 0..1000:
		p := promise(fn: ok(i * 2))
		n += p.wait().get_or(0)

	n

bench "promise.spawn_then_wait_5000" per 5000:
	var running List[Promise[Int]] = []
	for i in 0..5000:
		running.append(promise(fn: ok(i)))

	var n = 0
	for v in wait_all(running).get_or([]):
		n += v
	n
