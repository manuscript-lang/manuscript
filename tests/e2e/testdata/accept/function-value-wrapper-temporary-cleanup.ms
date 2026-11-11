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
		append_file(self.path, "{self.id},").wait()?
		if self.id == 98: return error(Error("failed close"))

		self.path = "closed"

fn present(path: String, id: Int) Resource?: Resource(id, path.clone())

fn log_text(path: String) String!:
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)

fn observed(value: Resource?) Bool: value.is_some()

fn observed_default(value: Resource?, tail: Int = 0) Bool:
	return value.is_some() or tail > 0

fn rejected() Int!: error(Error("expected"))

fn accepted() Int!: ok(1)

fn faulted() Int: [1].get(3)

fn later_error(reader: fn(Resource?, Resource?, Int) Bool, path: String) Unit!:
	_used := reader(present(path, 10), present(path, 11), rejected()?)

fn later_success(reader: fn(Resource?, Resource?, Int) Bool, path: String) Unit!:
	_used := reader(present(path, 12), present(path, 13), accepted()?)

fn later_fault(reader: fn(Resource?, Resource?, Int) Bool, path: String) Unit:
	_used := reader(present(path, 14), present(path, 15), faulted())

fn new_owner_fault(path: String) Unit:
	create := fn(value: Resource?, target: String) Resource:
		if value.is_some(): return Resource(50, target.clone())
		return Resource(51, target.clone())

	owner := create(present(path, 49), path)
	_used := owner.id + faulted()

fn failed_close(path: String) Unit:
	owner := Resource(99, path.clone())
	reader := fn(value: Resource?) Bool: value.is_some()
	_used := reader(present(path, 98))
	_id := owner.id

test "lambda and source function aliases close temporary wrappers once":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	reader := fn(value: Resource?) Bool: value.is_some()
	expect_equal(reader(present(path, 1)), true)?

	source := observed
	expect_equal(source(present(path, 2)), true)?
	expect_equal(log_text(path)?, "1,2,")?

	named := present(path, 3)
	expect_equal(reader(named), true)?
	expect_equal(source(named), true)?
	expect_equal(log_text(path)?, "1,2,")?

test "function arguments remain protected through later try and faults":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	reader := fn(first: Resource?, second: Resource?, tail: Int) Bool:
		return first.is_some() or second.is_some() or tail > 0
	expect_equal(later_error(reader, path).is_error(), true)?
	later_success(reader, path)?

	_fault := expect_fault(fn: later_fault(reader, path))?
	expect_equal(log_text(path)?, "11,10,13,12,15,14,")?

test "function dispatch errors and faults retain temporary cleanup":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	reject := fn(value: Resource?) Unit!:
		if value.is_some(): return error(Error("expected"))
		return ok(unit)

	broken := fn(value: Resource?) Unit:
		if value.is_some(): _bad := [1].get(3)
	expect_equal(reject(present(path, 20)).is_error(), true)?

	_fault := expect_fault(fn: broken(present(path, 21)))?
	_new := expect_fault(fn: new_owner_fault(path))?
	expect_equal(log_text(path)?, "20,21,49,50,")?

test "function default adapters retain caller resource ownership":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	reader := observed_default
	expect_equal(reader(present(path, 30)), true)?
	expect_equal(reader(present(path, 31), 1), true)?

	named := present(path, 32)
	expect_equal(reader(named), true)?
	expect_equal(reader(named, 1), true)?
	expect_equal(log_text(path)?, "30,31,")?

test "function failed temporary close retains older caller owner":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	_fault := expect_fault(fn: failed_close(path))?
	expect_equal(log_text(path)?, "98,99,")?

fn wrapped_result(path: String) Result[Resource, String]:
	return ok(Resource(70, path.clone()))

test "function Result and loop condition temporaries close each time":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	result := fn(value: Result[Resource, String]) Bool: value.is_ok()
	expect_equal(result(wrapped_result(path)), true)?
	expect_equal(result(error("absent")), false)?

	reader := fn(value: Resource?) Bool: value.is_some()
	var count = 0

	while count < 3 and reader(present(path, 80)):
		count += 1
		if count == 1: continue
		if count == 3: break

	expect_equal(log_text(path)?, "70,80,80,80,")?

fn named_conversion_calls(path: String) Unit!:
	named := Resource(110, path.clone())
	lambda := fn(value: Resource?) Bool: value.is_some()
	source := observed_default
	expect_equal(lambda(named), true)?
	expect_equal(lambda(named), true)?
	expect_equal(source(named), true)?
	expect_equal(source(named, 1), true)?
	expect_equal(log_text(path)?, "")?
	expect_equal(named.id, 110)?

test "function Optional transport from a named payload remains a borrow":
	directory := temporary("fn-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	named_conversion_calls(path)?
	expect_equal(log_text(path)?, "110,")?
