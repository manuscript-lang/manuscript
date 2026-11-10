// expect-stdout: close 1
// expect-stdout: ordinary 2
// expect-stdout: close 2
// expect-stdout: default 34
// expect-stdout: close 3
// expect-stdout: generic 6
// expect-stdout: borrowed 8
// expect-stdout: close 4
// expect-stdout: after borrowed
// expect-stdout: shared 13
// expect-stdout: close 7
// expect-stdout: after shared
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

impl Closeable for Marker:
	var fn close() Unit!:
		print("close {self.id}")

impl Marker:
	fn status() Int: self.id

	fn with_default(offset: Int = 10) Int: self.id + offset

	fn generic[T](_tag: T) Int: self.id

	var fn bump(delta: Int = 1) Int:
		self.id += delta
		return self.id

fn marker(id: Int) Marker: Marker(id)

fn ordinary() Int:
	read := marker(1).status
	first := read()
	return first + read()

fn defaulted() Int:
	read := marker(2).with_default
	first := read()
	return first + read(20)

fn generic() Int:
	read := marker(3).generic[Int]
	first := read(10)
	return first + read(20)

fn borrow(value: Marker) Int:
	read := value.status
	first := read()
	return first + read()

fn borrowed_owner() Unit:
	value := marker(4)
	answer := borrow(value)
	print("borrowed {answer}")

	_still_present := value.id

fn shared(var value: Marker) Int:
	bump := value.bump
	first := bump()
	return first + bump(1)

fn shared_owner() Unit:
	var value = marker(5)
	answer := shared(var value)
	print("shared {answer}")

	_still_present := value.id

fn main() Unit:
	a := ordinary()
	print("ordinary {a}")

	b := defaulted()
	print("default {b}")

	c := generic()
	print("generic {c}")
	borrowed_owner()
	print("after borrowed")
	shared_owner()
	print("after shared")
