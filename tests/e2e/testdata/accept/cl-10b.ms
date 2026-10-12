import List from "@std/collections.ms"
import Optional from "@std/optional.ms"

interface ReadValue[T]:
    fn get() -> T

type Box[T]:
    value: T

type ReaderHolder:
    reader: ReadValue[Int]

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

fn make_view[T: ReadValue[Int]](source: T) -> ReadValue[Int]:
    return ReadValue[Int](value: source)

fn forward_view[T: ReadValue[Int]](source: T) -> ReadValue[Int]:
    return ReadValue[Int](value: source)

fn consume[T: ReadValue[Int]](source: T) -> Int:
    return source.get()

test "contract views and callbacks":
    let box = Box[Int](value: 7)
    let first = make_view(source: box)
    let forwarded = forward_view(source: box)
    let identity = ReadValue[Int](value: forwarded)
    let copied = ReadValue[Int](value: identity)
    let holder = ReaderHolder(reader: identity)
    let readers: List[ReadValue[Int]] = [holder.reader]
    let optional: Optional[ReadValue[Int]] = some(value: forwarded)
    let callback = CallbackReader(read_value: seven)
    let callback_view = ReadValue[Int](value: callback)
    assert first.get() == 7
    assert copied.get() == 7
    assert callback_view.get() == 7
    assert consume(source: holder.reader) == 7
