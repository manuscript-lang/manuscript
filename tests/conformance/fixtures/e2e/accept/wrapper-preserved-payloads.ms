// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String

fn move Marker.close() Void!: append_file(self.log, f"{self.id},").wait()

fn optional_cause(move log: String) Void:
	value: Marker? := Marker(1, log)
	_kept := value.ok_or("failure")

fn optional_callback(move log: String) Void:
	value: Marker? := Marker(2, log)
	_kept := value.ok_or_else(fn: "failure")

fn result_error_map(move log: String) Void:
	value: Marker!Int := ok(Marker(3, log))
	_kept := value.map_error(fn cause: cause + 1)

fn result_optional(move log: String) Void:
	value: Marker!Int := ok(Marker(4, log))
	_kept := value.to_optional()

fn result_map(move log: String) Void:
	value: Int!Marker := error(Marker(5, log))
	_kept := value.map(fn item: item + 1)

fn result_then(move log: String) Void:
	value: Int!Marker := error(Marker(6, log))
	_kept := value.and_then(fn item: ok(item + 1))

fn error_result(id: Int, move log: String) Int!Marker: error(Marker(id, log))

fn discarded_error(move log: String) Void:
	_kept := error_result(7, log).to_optional()

fn transformed_success(log: String) Void!:
	value: Marker!Int := ok(Marker(8, log.clone()))
	mapped := value.map(fn item: Marker(item.id + 1, log.clone()))
	expect_equal(mapped.get().id, 9)?

fn transformed_error(log: String) Void!:
	value: Int!Marker := error(Marker(10, log.clone()))
	mapped := value.map_error(fn item: Marker(item.id + 1, log.clone()))
	expect_equal(mapped.is_error(), true)?

fn transformed_then(log: String) Void!:
	value: Marker!Int := ok(Marker(12, log.clone()))
	mapped: Marker!Int := value.and_then(fn item: ok(Marker(item.id + 1, log.clone())))
	expect_equal(mapped.get().id, 13)?

test "preserved resource payloads transfer exactly once":
	tmp := temporary("wrapper-preserved-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	optional_cause(log.clone())
	optional_callback(log.clone())
	result_error_map(log.clone())
	result_optional(log.clone())
	result_map(log.clone())
	result_then(log.clone())
	discarded_error(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "1,2,3,4,5,6,7,")?
	transformed_success(log.clone())?
	transformed_error(log.clone())?
	transformed_then(log.clone())?
	expect_equal(
		read_file(log).wait().get().decode_utf8() or "",
		"1,2,3,4,5,6,7,8,9,10,11,12,13,",
	)?

// `map` takes the Result; its callback reads the resource, which closes after the call.
fn transform_once(log: String) Void!:
	value: Marker!Int := ok(Marker(20, log.clone()))
	mapped := value.map(fn item: Marker(item.id + 1, log.clone()))
	expect_equal(mapped.get().id, 21)?

test "map takes a resource payload while reusable methods copy only retained data":
	tmp := temporary("wrapper-callback-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	transform_once(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "20,21,")?

	data: String!Int := ok("payload")
	convert := fn: data.clone().to_optional()
	expect_equal(convert().get(), "payload")?
	expect_equal(convert().get(), "payload")?
	expect_equal(data.get(), "payload")?

test "empty and transformed branches do not manufacture retained payloads":
	absent: Int? := null
	expect_equal(absent.ok_or("failure").is_error(), true)?
	expect_equal(absent.ok_or_else(fn: "failure").is_error(), true)?

	failed: Int!Int := error(3)
	expect_equal(failed.map_error(fn cause: cause + 1).is_error(), true)?
	expect_equal(failed.to_optional() == null, true)?

	success: Int!Int := ok(5)
	expect_equal(success.map(fn item: item + 1).get(), 6)?
	expect_equal(success.and_then(fn item: ok(item + 2)).get(), 7)?

fn named_error(log: String) Void!:
	value := error_result(31, log.clone())
	absent := value.to_optional()
	expect_equal(absent == null, true)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "30,31,")?

test "discarded owned errors close, named ones too once to_optional moves them":
	tmp := temporary("wrapper-errors-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?

	absent := error_result(30, log.clone()).to_optional()
	expect_equal(absent == null, true)?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "30,")?
	named_error(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "30,31,")?

fn specialized_optional[T](create: fn() Int, value: T?) T!Int:
	return value.ok_or_else[Int](create)

fn specialized_error[T](value: Int!T) String!T:
	return value.map[String](fn item: f"{item}")

fn specialized_transfers(move log: String) Void:
	present: Marker? := Marker(60, log.clone())
	_first := specialized_optional(fn: 0, present)
	failed: Int!Marker := error(Marker(61, log))
	_second := specialized_error(failed)

test "specialized direct generic methods transfer instead of retaining reusable captures":
	tmp := temporary("wrapper-specialized-") | expect_ok?
	log := f"{tmp.path()}/log"
	write_file(log, "").wait()?
	specialized_transfers(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8() or "", "61,60,")?

type Box:
	items: List[Int]

fn Box.read[T](_tag: T) List[Int]: self.items

fn var Box.change[T](_tag: T) Int:
	self.items.append(3)
	return self.items.length()

test "specialized source methods and indexed function calls keep their receiver paths":
	var box = Box([1, 2])
	expect_equal(box.read[Int](0).length(), 2)?
	expect_equal(box.change[Int](0), 3)?
	expect_equal(box.items, [1, 2, 3])?

	callbacks := [fn(value: Int) Int: value + 1]
	expect_equal(callbacks[0](4), 5)?
