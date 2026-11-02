# The count gate requires zero live heap blocks in both builds after cancellation and
# a guarded read fault or a fault during normal close. A correct close count alone can hide a leaked interface box.
import Closeable, panic from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ReadStream, IoError from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import Duration, nanoseconds, sleep from "@std/os/time.ms"

type Source:
    closes: Shared[Int]
    action: Int

impl ReadStream for Source:
    var fn read(max_bytes: Int?) Bytes?!IoError:
        if self.action == 1: sleep(nanoseconds(500000000))
        if self.action == 3: panic("read failed")
        return ok(none)

    var fn close() Unit:
        var count = lock(self.closes)
        count.value += 1
        count.close().get()
        if self.action == 2: panic("close failed")
        return unit

type Wrapper:
    input: ReadStream

impl Closeable for Wrapper:
    var fn close() Unit!:
        self.input.close()
        return ok(unit)

impl Wrapper:
    var fn read(choice: Bool) Bytes?!IoError:
        if choice: return self.input.read(1)

        return self.input.read(2)

fn run(closes: Shared[Int], action: Int, choice: Bool) Int:
    var wrapper = Wrapper(Source(closes, action))
    let _result = wrapper.read(choice)
    return 0

export fn main() Int:
    for action in [1, 2, 3]:
        for choice in [false, true]:
            let closes = share(0)
            let captured = closes
            var timeout: Duration? = none
            if action == 1: timeout = nanoseconds(20000000)

            var group = TaskGroup[Int](timeout: timeout, contain_faults: true)
            let task = group.spawn(fn channel: run(captured, action, choice))
            let result = task.result()
            if result.is_ok(): return 1

            group.close().get()
            if closes.get() != 1: return 2

    return 0
