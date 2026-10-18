import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
import Synchronized from "@std/sync.ms"

interface OtherClose:
    fn close(flag: Bool) Int

interface Disposable:
    fn close() Unit

type Resource:
    closed: Synchronized[Bool]

impl OtherClose for Resource:
    fn close(flag: Bool) Int:
        return panic("Unexpected case")

impl Closeable for Resource:
    fn close() Unit:
        with locked = self.closed.lock():
            locked.set(true)

impl Disposable for Resource:
    fn close() Unit:
        with locked = self.closed.lock():
            locked.set(true)

fn bound_cleanup[T: Disposable](resource: T) Unit:
    with item = resource:
        return unit

fn canonical_cleanup[T: Closeable](resource: T) Unit:
    with item = resource:
        return unit

test "cleanup uses the selected contract":
    let closed = Synchronized(false)
    with resource = Resource(closed):
        with locked = closed.lock():
            if not (not locked.get()):
                return panic("check failed")
    with locked = closed.lock():
        if not (locked.get()):
            return panic("check failed")
    with locked = closed.lock():
        locked.set(false)
    bound_cleanup(Resource(closed))
    with locked = closed.lock():
        if not (locked.get()):
            return panic("check failed")
    with locked = closed.lock():
        locked.set(false)
    canonical_cleanup(Resource(closed))
    with locked = closed.lock():
        if not (locked.get()):
            return panic("check failed")
