import panic from "@std/faults.ms"

import List from "@std/collections.ms"
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

test "atomic state and sealed builders":
    let state = Synchronized(value: 3)
    with locked = state.lock():
        if not (locked.get() == 3):
            return panic(message: "check failed")
        locked.set(value: 4)
    with locked = state.lock():
        if not (locked.get() == 4):
            return panic(message: "check failed")
    let list = ListBuilder[Int]()
    list.append(value: 1)
    list.append(value: 2)
    if not (list.freeze() == [1, 2]):
        return panic(message: "check failed")
    if not (list.freeze() == [1, 2]):
        return panic(message: "check failed")
    let map = MapBuilder[String, Int]()
    map.with_entry(key: "a", value: 1)
    map.with_entry(key: "a", value: 2)
    let expected: Optional[Int] = some(value: 2)
    if not (map.freeze().get(key: "a") == expected):
        return panic(message: "check failed")
    let set = SetBuilder[Int]()
    set.with_value(value: 3)
    set.with_value(value: 3)
    if not (set.freeze().length() == 1):
        return panic(message: "check failed")
    let bytes = BytesBuilder()
    bytes.append(value: 65)
    bytes.concat(values: "B".to_bytes())
    let expected_text: Optional[String] = some(value: "AB")
    if not (bytes.freeze().to_text() == expected_text):
        return panic(message: "check failed")
    let text = StringBuilder()
    text.append(value: "hello")
    text.append(value: " world")
    if not (text.freeze() == "hello world"):
        return panic(message: "check failed")

test "pool leases guard aliases and release resources":
    let closed = Synchronized(value: false)
    let original = (File)(value: MemoryFile(closed: closed))
    with pool = Pool(resources: [original]):
        match pool.acquire():
            error(_):
                return panic(message: "Unexpected case")
            ok(acquired):
                with lease = acquired:
                    match lease.get():
                        error(_):
                            return panic(message: "Unexpected case")
                        ok(alias):
                            lease.close()
                            match alias.read(max_bytes: 4):
                                ok(_):
                                    return panic(message: "Unexpected case")
                                error(cause):
                                    if not (cause == IoError.Closed):
                                        return panic(message: "check failed")
                match acquired.get():
                    ok(_):
                        return panic(message: "Unexpected case")
                    error(cause):
                        if not (cause == PoolError.Closed):
                            return panic(message: "check failed")
        with locked = closed.lock():
            if not (not locked.get()):
                return panic(message: "check failed")
    with locked = closed.lock():
        if not (locked.get()):
            return panic(message: "check failed")
