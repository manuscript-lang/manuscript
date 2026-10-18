import {expect_equal} from "@std/testing.ms"

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
    return ReadValue[Int](source)

fn forward_view[T: ReadValue[Int]](source: T) -> ReadValue[Int]:
    return ReadValue[Int](source)

fn consume[T: ReadValue[Int]](source: T) -> Int:
    return source.get()

test "contract views and callbacks":
    let box = Box[Int](7)
    let first = make_view(source: box)
    let forwarded = forward_view(source: box)
    let identity = ReadValue[Int](forwarded)
    let copied = ReadValue[Int](identity)
    let holder = ReaderHolder(identity)
    let readers: List[ReadValue[Int]] = [holder.reader]
    let optional: Optional[ReadValue[Int]] = some(forwarded)
    let callback = CallbackReader(seven)
    let callback_view = ReadValue[Int](callback)
    first.get() | try expect_equal(expected: 7)
    copied.get() | try expect_equal(expected: 7)
    callback_view.get() | try expect_equal(expected: 7)
    consume(source: holder.reader) | try expect_equal(expected: 7)
