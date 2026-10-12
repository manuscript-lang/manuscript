import List from "@std/collections.ms"
import Queue from "@std/queues.ms"
import QueueError from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import Pool from "@std/pools.ms"
import PoolError from "@std/pools.ms"
import File from "@std/io.ms"
import IoError from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import ListBuilder from "@std/builders.ms"
import MapBuilder from "@std/builders.ms"
import SetBuilder from "@std/builders.ms"
import BytesBuilder from "@std/builders.ms"
import StringBuilder from "@std/builders.ms"

type MemoryFile:
    closed: Synchronized[Bool]

impl File for MemoryFile:
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]:
        with locked = self.closed.lock():
            if locked.get():
                return error(cause: IoError.Closed)
        return ok(value: some(value: "data".to_bytes()))
    fn close() -> Unit:
        with locked = self.closed.lock():
            locked.set(value: true)

test "bounded queues drain on close":
    with queue = Queue[Int](capacity: 2):
        let accepted = queue.send(value: 3)
        let second = queue.send(value: 4)
        queue.close()
        match queue.receive():
            some(value):
                assert value == 3
            none:
                assert false
        match queue.receive():
            some(value):
                assert value == 4
            none:
                assert false
        match queue.receive():
            some(_):
                assert false
            none:
                assert true
        match queue.send(value: 5):
            ok(_):
                assert false
            error(cause):
                assert cause == QueueError.Closed

test "atomic state and sealed builders":
    let state = Synchronized(value: 3)
    with locked = state.lock():
        assert locked.get() == 3
        locked.set(value: 4)
    with locked = state.lock():
        assert locked.get() == 4
    let list = ListBuilder[Int]()
    list.append(value: 1)
    list.append(value: 2)
    assert list.freeze() == [1, 2]
    assert list.freeze() == [1, 2]
    let map = MapBuilder[String, Int]()
    map.with_entry(key: "a", value: 1)
    map.with_entry(key: "a", value: 2)
    let expected: Optional[Int] = some(value: 2)
    assert map.freeze().get(key: "a") == expected
    let set = SetBuilder[Int]()
    set.with_value(value: 3)
    set.with_value(value: 3)
    assert set.freeze().length() == 1
    let bytes = BytesBuilder()
    bytes.append(value: 65)
    bytes.concat(values: "B".to_bytes())
    let expected_text: Optional[String] = some(value: "AB")
    assert bytes.freeze().to_text() == expected_text
    let text = StringBuilder()
    text.append(value: "hello")
    text.append(value: " world")
    assert text.freeze() == "hello world"

test "pool leases guard aliases and release resources":
    let closed = Synchronized(value: false)
    let original = (File)(value: MemoryFile(closed: closed))
    with pool = Pool(resources: [original]):
        match pool.acquire():
            error(_):
                assert false
            ok(acquired):
                with lease = acquired:
                    match lease.get():
                        error(_):
                            assert false
                        ok(alias):
                            lease.close()
                            match alias.read(max_bytes: 4):
                                ok(_):
                                    assert false
                                error(cause):
                                    assert cause == IoError.Closed
                match acquired.get():
                    ok(_):
                        assert false
                    error(cause):
                        assert cause == PoolError.Closed
        with locked = closed.lock():
            assert not locked.get()
    with locked = closed.lock():
        assert locked.get()
