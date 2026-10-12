import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

interface ReadValue[T]:
    fn get() -> T

type Box[T]:
    value: T

type SharedReader:
    reader: ReadValue[Int] & Shareable

type CallbackReader:
    read_value: fn() -> Int

impl ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value

impl ReadValue[Int] for CallbackReader:
    fn get() -> Int:
        return self.read_value()

fn seven() -> Int:
    return 7

fn local_view[T: ReadValue[Int]](source: T) -> ReadValue[Int]:
    return ReadValue[Int](value: source)

fn shared_view[T: ReadValue[Int] & Shareable](source: T) -> ReadValue[Int] & Shareable:
    return (ReadValue[Int] & Shareable)(value: source)

fn consume_shared[T: ReadValue[Int] & Shareable](source: T) -> Int:
    return source.get()

test "plain and shared views":
    let box = Box[Int](value: 7)
    let plain = local_view(source: box)
    let shared = shared_view(source: box)
    let identity = (ReadValue[Int] & Shareable)(value: shared)
    let erased = ReadValue[Int](value: identity)
    let holder = SharedReader(reader: identity)
    let readers: List[ReadValue[Int] & Shareable] = [holder.reader]
    let optional: Optional[ReadValue[Int] & Shareable] = some(value: shared)
    let callback = CallbackReader(read_value: seven)
    let local_callback = ReadValue[Int](value: callback)
    if not (plain.get() == 7):
        return panic(message: "check failed")
    if not (erased.get() == 7):
        return panic(message: "check failed")
    if not (local_callback.get() == 7):
        return panic(message: "check failed")
    if not (consume_shared(source: holder.reader) == 7):
        return panic(message: "check failed")
