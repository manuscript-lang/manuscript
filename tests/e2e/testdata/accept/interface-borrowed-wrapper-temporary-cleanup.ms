import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_fault, expect_some from "@std/test/test.ms",
)

type Resource:
	id: Int
	path: String

impl Closeable for Resource:
	var fn close() Unit!:
		try append_file(self.path, "{self.id},").wait()
		if self.id == 98: return error(Error("failed close"))

		self.path = "closed"

interface Observer:
	fn observe(first: Resource?, second: Resource?, tail: Int? = none) Bool
	fn reject(value: Resource?) Unit!
	fn broken(value: Resource?) Unit
	fn create(value: Resource?, path: String) Resource
	fn change(var value: Resource) Unit
	fn fault_with_var(var value: Resource) Unit
	fn result(value: Result[Resource, String]) Bool

type Reader:
	tag: Int

impl Observer for Reader:
	fn observe(first: Resource?, second: Resource?, tail: Int? = none) Bool:
		return first.is_some() or second.is_some() or tail.get(0) > 0

	fn reject(value: Resource?) Unit!:
		if value.is_some(): return error(Error("expected"))

	fn broken(value: Resource?) Unit:
		if value.is_some(): _bad := [1].get(3)

	fn create(value: Resource?, path: String) Resource:
		if value.is_some(): return Resource(50, path.clone())
		return Resource(51, path.clone())

	fn change(var value: Resource) Unit:
		value.id += 1

	fn fault_with_var(var value: Resource) Unit:
		_bad := [value.id].get(3)

	fn result(value: Result[Resource, String]) Bool: value.is_ok()

fn present(path: String, id: Int) Resource?: Resource(id, path.clone())

fn log_text(path: String) String!:
	bytes := try read_file(path).wait()
	return ok(try expect_some(bytes.decode_utf8()))

fn rejected() Int!: error(Error("expected"))

fn accepted() Int!: ok(1)

fn faulted() Int: [1].get(3)

fn later_error(reader: Observer, path: String) Unit!:
	_used := reader.observe(present(path, 10), present(path, 11), try rejected())

fn later_success(reader: Observer, path: String) Unit!:
	_used := reader.observe(present(path, 12), present(path, 13), try accepted())

fn later_fault(reader: Observer, path: String) Unit:
	_used := reader.observe(present(path, 14), present(path, 15), faulted())

fn new_owner_fault(reader: Observer, path: String) Unit:
	owner := reader.create(present(path, 49), path)
	_used := owner.id + faulted()

fn failed_close(reader: Observer, path: String) Unit:
	owner := Resource(99, path.clone())
	_used := reader.observe(present(path, 98), none)
	_id := owner.id

test "interface borrows intact temporary wrappers in written order":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	try expect_equal(reader.observe(Resource(1, path.clone()), present(path, 2)), true)
	try expect_equal(try log_text(path), "2,1,")
	try expect_equal(
		reader.observe(second: present(path, 3), first: present(path, 4)),
		true,
	)
	try expect_equal(try log_text(path), "2,1,4,3,")

	named := present(path, 5)
	try expect_equal(reader.observe(named, none), true)
	try expect_equal(reader.observe(named, none), true)
	try expect_equal(try log_text(path), "2,1,4,3,")

test "interface arguments retain cleanup through later try and faults":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	try expect_equal(later_error(reader, path).is_error(), true)
	try later_success(reader, path)

	_fault := try expect_fault(fn: later_fault(reader, path))
	try expect_equal(try log_text(path), "11,10,13,12,15,14,")

test "interface callee errors faults and new owners preserve cleanup":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	try expect_equal(reader.reject(present(path, 20)).is_error(), true)

	_fault := try expect_fault(fn: reader.broken(present(path, 21)))
	_new := try expect_fault(fn: new_owner_fault(reader, path))
	try expect_equal(try log_text(path), "20,21,49,50,")

test "interface resource var arguments preserve their owners":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	var named = Resource(30, path.clone())
	reader.change(var named)
	try expect_equal(named.id, 31)
	try expect_equal(try log_text(path), "")

test "interface failed temporary close leaves older owner registered":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	_fault := try expect_fault(fn: failed_close(reader, path))
	try expect_equal(try log_text(path), "98,99,")

fn named_var_fault(reader: Observer, path: String) Unit:
	var value = Resource(60, path.clone())
	reader.fault_with_var(var value)

fn wrapped_result(path: String) Result[Resource, String]:
	return ok(Resource(70, path.clone()))

test "interface var fault retains the caller cleanup":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	_fault := try expect_fault(fn: named_var_fault(reader, path))
	try expect_equal(try log_text(path), "60,")

test "interface Result temporaries and loop conditions keep cleanup bounded":
	directory := try temporary("iface-wrapper-")
	path := "{directory.path()}/log"
	try write_file(path, "").wait()

	reader: Observer := Reader(1)
	try expect_equal(reader.result(wrapped_result(path)), true)
	try expect_equal(reader.result(error("absent")), false)

	var count = 0

	while count < 3 and reader.observe(present(path, 80), none):
		count += 1
		if count == 1: continue
		if count == 3: break

	try expect_equal(try log_text(path), "70,80,80,80,")
