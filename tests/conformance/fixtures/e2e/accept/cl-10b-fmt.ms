# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interfaces,lists,modules,optional,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-10b.ms
import {expect_equal} from "@std/testing.ms"

interface ReadValue[T]:
    fn get() ref T

type Box[T]:
    value: T

type ReaderHolder:
    reader: ReadValue[Int]

type CallbackReader:
    read_value: fn() Int

impl ReadValue[T] for Box[T]:
    fn get() ref T:
        return self.value

impl ReadValue[Int] for CallbackReader:
    fn get() Int:
        return self.read_value()

fn seven() Int:
    return 7

fn make_view[T: ReadValue[Int]](source: T) ReadValue[Int]:
    return ReadValue[Int](source)

fn forward_view[T: ReadValue[Int]](source: T) ReadValue[Int]:
    return ReadValue[Int](source)

fn consume[T: ReadValue[Int]](source: T) Int:
    return source.get()

test "contract views and callbacks":
    let box = Box[Int](7)
    let first = make_view(box)
    let forwarded = forward_view(box)
    let identity = ReadValue[Int](forwarded)
    let copied = ReadValue[Int](identity)
    let holder = ReaderHolder(identity)
    let _readers: List[ReadValue[Int]] = [holder.reader]
    let _optional: Optional[ReadValue[Int]] = some(forwarded)
    let callback = CallbackReader(seven)
    let callback_view = ReadValue[Int](callback)
    try expect_equal(first.get(), 7)
    try expect_equal(copied.get(), 7)
    try expect_equal(callback_view.get(), 7)
    try expect_equal(consume(holder.reader), 7)
