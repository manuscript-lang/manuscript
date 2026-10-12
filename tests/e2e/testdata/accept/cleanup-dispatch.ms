import panic from "@std/faults.ms"

import Closeable from "@std/cleanup.ms"
import State from "@std/state.ms"

interface OtherClose:
    fn close(flag: Bool) -> Int

interface Disposable:
    fn close() -> Unit

type Resource:
    closed: State[Bool]

impl OtherClose for Resource:
    fn close(flag: Bool) -> Int:
        return panic(message: "Unexpected case")
        return 0

impl Closeable for Resource:
    fn close() -> Unit:
        self.closed.set(value: true)

impl Disposable for Resource:
    fn close() -> Unit:
        self.closed.set(value: true)

fn bound_cleanup[T: Disposable](resource: T) -> Unit:
    with item = resource:
        let completed = unit

fn canonical_cleanup[T: Closeable](resource: T) -> Unit:
    with item = resource:
        let completed = unit

test "cleanup uses the selected contract":
    let closed = State(value: false)
    with resource = Resource(closed: closed):
        if not (not closed.get()):
            return panic(message: "check failed")
    if not (closed.get()):
        return panic(message: "check failed")
    closed.set(value: false)
    bound_cleanup(resource: Resource(closed: closed))
    if not (closed.get()):
        return panic(message: "check failed")
    closed.set(value: false)
    canonical_cleanup(resource: Resource(closed: closed))
    if not (closed.get()):
        return panic(message: "check failed")
