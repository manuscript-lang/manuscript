import {expect_true} from "@std/testing.ms"
import Closeable from "@std/cleanup.ms"
import Synchronized from "@std/sync.ms"

interface OtherClose:
    fn close(flag: Bool) -> Int

interface Disposable:
    fn close() -> Unit

type Resource:
    closed: Synchronized[Bool]
    unexpected: List[Int]

impl OtherClose for Resource:
    fn close(flag: Bool) -> Int:
        self.unexpected.append(1)
        return 0

impl Closeable for Resource:
    fn close() -> Unit:
        with locked = self.closed.lock():
            locked.set(value: true)

impl Disposable for Resource:
    fn close() -> Unit:
        with locked = self.closed.lock():
            locked.set(value: true)

fn bound_cleanup[T: Disposable](resource: T) -> Unit:
    with item = resource:
        let completed = unit

fn canonical_cleanup[T: Closeable](resource: T) -> Unit:
    with item = resource:
        let completed = unit

test "cleanup uses the selected contract":
    let closed = Synchronized(false)
    let unexpected: List[Int] = []
    with resource = Resource(closed, unexpected):
        with locked = closed.lock():
            (not locked.get()) | try expect_true
    with locked = closed.lock():
        (locked.get()) | try expect_true
    with locked = closed.lock():
        locked.set(value: false)
    bound_cleanup(resource: Resource(closed, unexpected))
    with locked = closed.lock():
        (locked.get()) | try expect_true
    with locked = closed.lock():
        locked.set(value: false)
    canonical_cleanup(resource: Resource(closed, unexpected))
    with locked = closed.lock():
        (locked.get()) | try expect_true
    unexpected.is_empty() | try expect_true
