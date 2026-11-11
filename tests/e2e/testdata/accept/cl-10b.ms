import expect_equal from "@std/test/test.ms"

interface ReadValue[T]:
	fn get() T

type Box[T: Clonable]:
	value: T

type ReaderHolder:
	reader: ReadValue[Int]

type CallbackReader:
	read_value: fn() Int

impl ReadValue[T] for Box[T]:
	fn get() T:
		return self.value.clone()

impl ReadValue[Int] for CallbackReader:
	fn get() Int:
		return self.read_value()

fn seven() Int:
	return 7

fn make_view[T: ReadValue[Int]](source: T) ReadValue[Int]:
	return source

fn forward_view[T: ReadValue[Int]](source: T) ReadValue[Int]:
	return source

fn consume[T: ReadValue[Int]](source: T) Int:
	return source.get()

test "contract views and callbacks":
	box := Box[Int](7)
	first := make_view(box)
	identity: ReadValue[Int] := forward_view(box.clone())
	copied: ReadValue[Int] := forward_view(box)
	holder := ReaderHolder(identity)
	_readers: List[ReadValue[Int]] := [forward_view(box.clone())]
	_optional: ReadValue[Int]? := forward_view(box)
	callback := CallbackReader(seven)
	callback_view: ReadValue[Int] := callback
	try expect_equal(first.get(), 7)
	try expect_equal(copied.get(), 7)
	try expect_equal(callback_view.get(), 7)
	try expect_equal(consume(holder.reader), 7)
