import Closeable from "@std/cleanup.ms"
import State from "@std/state.ms"

type OtherClose:
    fn close(flag: Bool) -> Int

type Disposable:
    fn close() -> Unit

type Resource:
    closed: State[Bool]

impl OtherClose for Resource:
    fn close(flag: Bool) -> Int:
        assert false
        return 0

impl Closeable for Resource:
    fn close() -> Unit:
        self.closed.set(value: true)

impl Disposable for Resource:
    fn close() -> Unit:
        self.closed.set(value: true)

fn bound_cleanup[T: Disposable](resource: T) -> Unit:
    with item = resource:
        assert true

fn canonical_cleanup[T: Closeable](resource: T) -> Unit:
    with item = resource:
        assert true

test "cleanup uses the selected contract":
    let closed = State(value: false)
    with resource = Resource(closed: closed):
        assert not closed.get()
    assert closed.get()
    closed.set(value: false)
    bound_cleanup(resource: Resource(closed: closed))
    assert closed.get()
    closed.set(value: false)
    canonical_cleanup(resource: Resource(closed: closed))
    assert closed.get()
