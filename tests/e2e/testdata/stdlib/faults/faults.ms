import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
import {ListBuilder} from "@std/collections.ms"
import {Queue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {stdout, WriteStream} from "@std/io.ms"

fn emit(message: String) Unit:
    if stdout().write(message.to_bytes()).is_error(): return panic(
        "fault transcript write failed"
    )

type Resource:
    output: WriteStream

impl Closeable for Resource:
    fn close() Unit:
        if self.output.write("fault cleanup completed\n".to_bytes()).is_error(): return panic(
            "cleanup transcript write failed"
        )

test "panic unwinds Closeable":
    with resource = Resource(stdout()):
        return panic("intentional stdlib panic")

test "absent Optional unwrap faults":
    let absent: Optional[Int] = none
    absent.unwrap()

test "sealed builder mutation faults":
    let builder = ListBuilder[Int]()
    builder.freeze()
    builder.append(1)

test "zero queue capacity faults":
    Queue[Int](0)

test "negative queue capacity faults":
    Queue[Int](-1)

test "stale synchronized guard faults":
    let state = Synchronized(1)
    let guard = state.lock()
    guard.close()
    guard.get()

test "unwrapping an out of range slice faults":
    ([1, 2]).slice(start: 0, end: 3).unwrap()

test "negative split limit faults":
    "a,b,c".split(separator: ",", max_parts: -1)

test "negative replace limit faults":
    "aaa".replace(old: "a", new: "b", max_replacements: -1)

test "runner continues with fresh roots after faults":
    emit("fresh root after stdlib faults\n")
