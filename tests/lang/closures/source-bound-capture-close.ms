// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker {
	id Int
	log String
	closed Bool = false
}

fn move Marker.close() Void! {
	if not self.closed {
		self.closed = true
		append_file(self.log, f"{self.id},").wait()?
	}
}

fn Marker.status() Int => self.id

fn Marker.with_default(offset Int = 10) Int => self.id + offset

fn Marker.generic[T](_value T) Int => self.id

fn var Marker.bump(delta Int = 1) Int {
	self.id += delta
	return self.id
}

fn marker(id Int, log String) Marker => Marker(id, log.clone())

fn ordinary(log String) Void! {
	status := marker(1, log).status
	expect_equal(status(), 1)?
	expect_equal(status(), 1)?
}

fn defaulted(log String) Void! {
	status := marker(2, log).with_default
	expect_equal(status(), 12)?
	expect_equal(status(20), 22)?
}

fn generic(log String) Void! {
	status := marker(3, log).generic[Int]
	expect_equal(status(10), 3)?
	expect_equal(status(20), 3)?
}

fn escaped(log String) fn() Int {
	value := marker(4, log)
	return value.status
}

fn escaping(log String) Void! {
	status := escaped(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,2,3,")?
	expect_equal(status(), 4)?
	expect_equal(status(), 4)?
}

fn borrow(value Marker) Void! {
	status := value.status
	with_default := value.with_default
	expect_equal(status(), 5)?
	expect_equal(with_default(), 15)?
}

fn borrowed(log String) Void! {
	value := marker(5, log.clone())
	borrow(value)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,2,3,4,")?
	expect_equal(value.status(), 5)?
}

test "nonmutating source default and generic method captures close their owners" {
	tmp := temporary("source-bound-close-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	ordinary(log.clone())?
	defaulted(log.clone())?
	generic(log.clone())?
	escaping(log.clone())?
	borrowed(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,2,3,4,5,")?
}

fn shared_default(var value Marker) Void! {
	bump := value.bump
	expect_equal(bump(), 8)?
	expect_equal(bump(2), 10)?
}

fn shared_owner(log String) Void! {
	var value = marker(7, log.clone())
	shared_default(value)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "")?
	expect_equal(value.status(), 10)?
}

test "shared source default method captures do not close the borrowed receiver" {
	tmp := temporary("source-bound-shared-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	shared_owner(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "10,")?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
