import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
	id: Int
	log: String

fn var Marker.close() Unit!: append_file(self.log, "{self.id},").wait()

fn optional_cause(log: String) Unit:
	value: Marker? := Marker(1, log)
	_kept := value.ok_or("failure")

fn optional_callback(log: String) Unit:
	value: Marker? := Marker(2, log)
	_kept := value.ok_or_else(fn: "failure")

fn result_error_map(log: String) Unit:
	value: Marker!Int := ok(Marker(3, log))
	_kept := value.map_error(fn cause: cause + 1)

fn result_optional(log: String) Unit:
	value: Marker!Int := ok(Marker(4, log))
	_kept := value.to_optional()

fn result_map(log: String) Unit:
	value: Int!Marker := error(Marker(5, log))
	_kept := value.map(fn item: item + 1)

fn result_then(log: String) Unit:
	value: Int!Marker := error(Marker(6, log))
	_kept := value.and_then(fn item: ok(item + 1))

fn error_result(id: Int, log: String) Int!Marker: error(Marker(id, log))

fn discarded_error(log: String) Unit:
	_kept := error_result(7, log).to_optional()

fn transformed_success(log: String) Unit!:
	value: Marker!Int := ok(Marker(8, log.clone()))
	mapped := value.map(fn item: Marker(item.id + 1, log.clone()))
	expect_equal(value.get().id, 8)?
	expect_equal(mapped.get().id, 9)?

fn transformed_error(log: String) Unit!:
	value: Int!Marker := error(Marker(10, log.clone()))
	mapped := value.map_error(fn item: Marker(item.id + 1, log.clone()))
	expect_equal(value.is_error(), true)?
	expect_equal(mapped.is_error(), true)?

fn transformed_then(log: String) Unit!:
	value: Marker!Int := ok(Marker(12, log.clone()))
	mapped: Marker!Int := value.and_then(fn item: ok(Marker(item.id + 1, log.clone())))
	expect_equal(value.get().id, 12)?
	expect_equal(mapped.get().id, 13)?

test "preserved resource payloads transfer exactly once":
	tmp := temporary("wrapper-preserved-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?
	optional_cause(log.clone())
	optional_callback(log.clone())
	result_error_map(log.clone())
	result_optional(log.clone())
	result_map(log.clone())
	result_then(log.clone())
	discarded_error(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,5,6,7,")?
	transformed_success(log.clone())?
	transformed_error(log.clone())?
	transformed_then(log.clone())?
	expect_equal(
		read_file(log).wait().get().decode_utf8().get(""),
		"1,2,3,4,5,6,7,8,9,11,10,12,13,",
	)?

fn bound_transform(log: String) Unit!:
	value: Marker!Int := ok(Marker(20, log.clone()))
	transform: fn(fn(Marker) Marker) Marker!Int := value.map[Marker]
	first := transform(fn item: Marker(item.id + 1, log.clone()))
	second := transform(fn item: Marker(item.id + 2, log.clone()))
	expect_equal(first.get().id, 21)?
	expect_equal(second.get().id, 22)?
	expect_equal(value.get().id, 20)?

test "callbacks borrow resource inputs while reusable methods copy only retained data":
	tmp := temporary("wrapper-callback-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?
	bound_transform(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "21,22,20,")?

	data: String!Int := ok("payload")
	convert := data.to_optional
	expect_equal(convert().get(), "payload")?
	expect_equal(convert().get(), "payload")?
	expect_equal(data.get(), "payload")?

test "empty and transformed branches do not manufacture retained payloads":
	absent: Int? := none
	expect_equal(absent.ok_or("failure").is_error(), true)?
	expect_equal(absent.ok_or_else(fn: "failure").is_error(), true)?

	failed: Int!Int := error(3)
	expect_equal(failed.map_error(fn cause: cause + 1).is_error(), true)?
	expect_equal(failed.to_optional().is_none(), true)?

	success: Int!Int := ok(5)
	expect_equal(success.map(fn item: item + 1).get(), 6)?
	expect_equal(success.and_then(fn item: ok(item + 2)).get(), 7)?

fn borrowed_error(log: String) Unit!:
	value := error_result(31, log.clone())
	absent := value.to_optional()
	expect_equal(absent.is_none(), true)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,")?
	expect_equal(value.is_error(), true)?

test "discarded owned errors close while borrowed errors stay alive":
	tmp := temporary("wrapper-errors-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?

	absent := error_result(30, log.clone()).to_optional()
	expect_equal(absent.is_none(), true)?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,")?
	borrowed_error(log.clone())?
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,31,")?

fn specialized_optional[T](value: T?, create: fn() Int) T!Int:
	return value.ok_or_else[Int](create)

fn specialized_error[T](value: Int!T) String!T:
	return value.map[String](fn item: "{item}")

fn specialized_transfers(log: String) Unit:
	present: Marker? := Marker(60, log.clone())
	_first := specialized_optional(present, fn: 0)
	failed: Int!Marker := error(Marker(61, log))
	_second := specialized_error(failed)

test "specialized direct generic methods transfer instead of retaining reusable captures":
	tmp := temporary("wrapper-specialized-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?
	specialized_transfers(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "61,60,")?

type Box:
	items: List[Int]

impl Box:
	fn read[T](_tag: T) List[Int]: self.items

	var fn change[T](_tag: T) Int:
		self.items.append(3)
		return self.items.length()

test "specialized source methods and indexed function calls keep their receiver paths":
	var box = Box([1, 2])
	expect_equal(box.read[Int](0).length(), 2)?
	expect_equal(box.change[Int](0), 3)?
	expect_equal(box.items, [1, 2, 3])?

	callbacks := [fn(value: Int) Int: value + 1]
	expect_equal(callbacks[0](4), 5)?
