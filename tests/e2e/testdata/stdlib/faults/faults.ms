import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
import {Optional} from "@std/optional.ms"
import {List, ListBuilder} from "@std/collections.ms"
import {Queue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {stdout, WriteStream} from "@std/io.ms"
import Result from "@std/result.ms"

fn emit(message: String) -> Unit:
    match stdout().write(message.to_bytes()):
        ok(_): return
        error(_): return panic("fault transcript write failed")

type Resource:
    output: WriteStream

impl Closeable for Resource:
    fn close() -> Unit:
        match self.output.write("fault cleanup completed\n".to_bytes()):
            ok(_): return
            error(_): return panic("cleanup transcript write failed")

test "panic unwinds Closeable":
    with resource = Resource(output: stdout()):
        return panic("intentional stdlib panic")

test "absent Optional unwrap faults":
    let absent: Optional[Int] = none
    let impossible = absent.unwrap()

test "sealed builder mutation faults":
    let builder = ListBuilder[Int]()
    let sealed = builder.freeze()
    builder.append(1)

test "zero queue capacity faults":
    let queue = Queue[Int](capacity: some(value: 0))

test "negative queue capacity faults":
    let queue = Queue[Int](capacity: some(value: -1))

test "stale synchronized guard faults":
    let state = Synchronized(value: 1)
    let guard = state.lock()
    guard.close()
    let impossible = guard.get()

test "invalid list slice faults":
    let impossible = ([1, 2]).slice(start: 0, end: 3)

test "runner continues with fresh roots after faults":
    emit("fresh root after stdlib faults\n")
