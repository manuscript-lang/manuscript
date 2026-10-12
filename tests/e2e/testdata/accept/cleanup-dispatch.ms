import panic from "@std/faults.ms"

import Closeable from "@std/cleanup.ms"
import Synchronized from "@std/sync.ms"

interface OtherClose:
    fn close(flag: Bool) -> Int

interface Disposable:
    fn close() -> Unit

type Resource:
    closed: Synchronized[Bool]

impl OtherClose for Resource:
    fn close(flag: Bool) -> Int:
        return panic(message: "Unexpected case")
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
    let closed = Synchronized(value: false)

    with resource = Resource(closed: closed):
        with locked = closed.lock():
            if not (not locked.get()):
                return panic(message: "check failed")

    with locked = closed.lock():
        if not (locked.get()):
            return panic(message: "check failed")

    with locked = closed.lock():
        locked.set(value: false)

    bound_cleanup(resource: Resource(closed: closed))

    with locked = closed.lock():
        if not (locked.get()):
            return panic(message: "check failed")

    with locked = closed.lock():
        locked.set(value: false)

    canonical_cleanup(resource: Resource(closed: closed))

    with locked = closed.lock():
        if not (locked.get()):
            return panic(message: "check failed")
