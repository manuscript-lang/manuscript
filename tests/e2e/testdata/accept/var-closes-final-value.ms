import Closeable from "@std/core.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import promise from "@std/concurrency/promise.ms"
import expect_equal, expect_ok from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

type Counter:
    value: Int
    log: String

impl Closeable for Counter:
    var fn close() Unit!:
        let _ = append_file(self.log, "{self.value},")
        return ok(unit)

fn logged(path: String) String:
    let read = read_file(path)
    if let bytes = read:
        return bytes.decode_utf8().get("")

    return ""

fn count_then_wait(log: String) Int:
    var counter = Counter(value: 0, log: log.clone())
    counter.value = 7
    sleep(nanoseconds(5000000000))
    counter.close().get(none)
    return 0

test "a var binding closes the value it ended with":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    var counter = Counter(value: 0, log: log.clone())
    counter.value = 5
    try counter.close()
    logged(log.clone()) | try expect_equal("5,")

fn cancel_counter(log: String) Unit:
    let work = promise(fn: ok(count_then_wait(log.clone())))
    let _ignored = work.wait(timeout: nanoseconds(20000000))

test "a cancelled var binding closes the value it had reached":
    let tmp = temporary("ms-log-") | try expect_ok
    let log = "{tmp.path()}/log"
    cancel_counter(log.clone())
    logged(log.clone()) | try expect_equal("7,")
