import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_some from "@std/test/test.ms",
)

type Marker:
	id: Int
	path: String

impl Closeable for Marker:
	var fn close() Unit!:
		try append_file(self.path, "{self.id},").wait()
		self.path = "closed"

type Held:
	id: Int
	path: String
	label: String

impl Closeable for Held:
	var fn close() Unit!:
		try append_file(self.path, "{self.id},").wait()
		self.path = "closed"

fn log_text(path: String) String!:
	bytes := try read_file(path).wait()
	return ok(try expect_some(bytes.decode_utf8()))

fn absent_cause(path: String) Bool:
	cause := Marker(1, path.clone())
	missing: Int? = none
	return missing.ok_or(cause).is_error()

fn present_cause(path: String) Bool:
	cause := Marker(2, path.clone())
	found: Int? = 7
	return found.ok_or(cause).is_ok()

fn temporary_cause(path: String) Bool:
	missing: Int? = none
	return missing.ok_or(Marker(3, path.clone())).is_error()

fn heap_cause(path: String) Bool:
	cause := Held(4, path.clone(), "heap-backed")
	missing: Int? = none
	return missing.ok_or(cause).is_error()

fn default_resource(path: String) Int:
	fallback := Marker(5, path.clone())
	missing: Marker? = none
	return missing.get(fallback).id

test "a resource passed to ok_or or get moves into the result and closes once":
	directory := try temporary("optional-argument-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()
	try expect_equal(absent_cause(path), true)
	try expect_equal(present_cause(path), true)
	try expect_equal(temporary_cause(path), true)
	try expect_equal(heap_cause(path), true)
	try expect_equal(default_resource(path), 5)
	try expect_equal(try log_text(path), "1,2,3,4,5,")
