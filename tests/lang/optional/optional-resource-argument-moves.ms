// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_some from "@std/test/test.ms",
)

type Marker {
	id Int
	path String
}

fn move Marker.close() Void! {
	append_file(self.path, f"{self.id},").wait()?
	self.path = "closed"
}

type Held {
	id Int
	path String
	label String
}

fn move Held.close() Void! {
	append_file(self.path, f"{self.id},").wait()?
	self.path = "closed"
}

fn log_text(path String) String! {
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)
}

fn absent_cause(path String) Bool {
	cause := Marker(1, path.clone())
	missing Int? := null
	return ok_or(missing, cause).is_error()
}

fn present_cause(path String) Bool {
	cause := Marker(2, path.clone())
	found Int? := 7
	return ok_or(found, cause).is_ok()
}

fn temporary_cause(path String) Bool {
	missing Int? := null
	return ok_or(missing, Marker(3, path.clone())).is_error()
}

fn heap_cause(path String) Bool {
	cause := Held(4, path.clone(), "heap-backed")
	missing Int? := null
	return ok_or(missing, cause).is_error()
}

fn default_resource(path String) Int {
	fallback := Marker(5, path.clone())
	missing Marker? := null
	return (missing.clone() or fallback).id
}

test "a resource passed to ok_or or get moves into the result and closes once" {
	directory := temporary("optional-argument-")?
	path := f"{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(absent_cause(path), true)?
	expect_equal(present_cause(path), true)?
	expect_equal(temporary_cause(path), true)?
	expect_equal(heap_cause(path), true)?
	expect_equal(default_resource(path), 5)?
	expect_equal(log_text(path)?, "1,2,3,4,5,")?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
