import (
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
	nanoseconds, sleep from "@std/time.ms",
)

type Counter:
	value: Int
	log: String

impl Closeable for Counter:
	var fn close() Unit!:
		_ := append_file(self.log, "{self.value},").wait()

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn count_then_wait(log: String) Int:
	var counter = Counter(value: 0, log: log.clone())
	counter.value = 7

	_ := sleep(nanoseconds(5000000000)).wait()
	counter.close().get(none)
	return 0

test "a var binding closes the value it ended with":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	var counter = Counter(value: 0, log: log.clone())
	counter.value = 5
	counter.close()?
	logged(log.clone()) | expect_equal("5,")?

fn cancel_counter(log: String) Unit:
	work := promise(fn: ok(count_then_wait(log.clone())))
	_ignored := work.with(
		options: PromiseOptions(timeout: nanoseconds(20000000))
	).wait()

test "a cancelled var binding closes the value it had reached":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	cancel_counter(log.clone())
	logged(log.clone()) | expect_equal("7,")?
