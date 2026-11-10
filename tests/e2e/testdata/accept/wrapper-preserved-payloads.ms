import (
    Closeable from "@std/core.ms",
    append_file, read_file, temporary, write_file from "@std/os/fs.ms",
    expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
    id: Int
    log: String

impl Closeable for Marker:
    var fn close() Unit!: append_file(self.log, "{self.id},").wait()

fn optional_cause(log: String) Unit:
    let value: Marker? = Marker(1, log)
    let _kept = value.ok_or("failure")

fn optional_callback(log: String) Unit:
    let value: Marker? = Marker(2, log)
    let _kept = value.ok_or_else(fn: "failure")

fn result_error_map(log: String) Unit:
    let value: Marker!Int = ok(Marker(3, log))
    let _kept = value.map_error(fn cause: cause + 1)

fn result_optional(log: String) Unit:
    let value: Marker!Int = ok(Marker(4, log))
    let _kept = value.to_optional()

fn result_map(log: String) Unit:
    let value: Int!Marker = error(Marker(5, log))
    let _kept = value.map(fn item: item + 1)

fn result_then(log: String) Unit:
    let value: Int!Marker = error(Marker(6, log))
    let _kept = value.and_then(fn item: ok(item + 1))

fn error_result(id: Int, log: String) Int!Marker: error(Marker(id, log))

fn discarded_error(log: String) Unit:
    let _kept = error_result(7, log).to_optional()

fn transformed_success(log: String) Unit!:
    let value: Marker!Int = ok(Marker(8, log.clone()))
    let mapped = value.map(fn item: Marker(item.id + 1, log.clone()))
    try expect_equal(value.get().id, 8)
    try expect_equal(mapped.get().id, 9)
    return ok(unit)

fn transformed_error(log: String) Unit!:
    let value: Int!Marker = error(Marker(10, log.clone()))
    let mapped = value.map_error(fn item: Marker(item.id + 1, log.clone()))
    try expect_equal(value.is_error(), true)
    try expect_equal(mapped.is_error(), true)
    return ok(unit)

fn transformed_then(log: String) Unit!:
    let value: Marker!Int = ok(Marker(12, log.clone()))
    let mapped: Marker!Int = value.and_then(
        fn item: ok(Marker(item.id + 1, log.clone()))
    )
    try expect_equal(value.get().id, 12)
    try expect_equal(mapped.get().id, 13)
    return ok(unit)

test "preserved resource payloads transfer exactly once":
    let tmp = temporary("wrapper-preserved-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()
    optional_cause(log.clone())
    optional_callback(log.clone())
    result_error_map(log.clone())
    result_optional(log.clone())
    result_map(log.clone())
    result_then(log.clone())
    discarded_error(log.clone())
    try expect_equal(
        read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,5,6,7,"
    )
    try transformed_success(log.clone())
    try transformed_error(log.clone())
    try transformed_then(log.clone())
    try expect_equal(
        read_file(log).wait().get().decode_utf8().get(""),
        "1,2,3,4,5,6,7,8,9,11,10,12,13,"
    )

fn bound_transform(log: String) Unit!:
    let value: Marker!Int = ok(Marker(20, log.clone()))
    let transform: fn(fn(Marker) Marker) Marker!Int = value.map[Marker]
    let first = transform(fn item: Marker(item.id + 1, log.clone()))
    let second = transform(fn item: Marker(item.id + 2, log.clone()))
    try expect_equal(first.get().id, 21)
    try expect_equal(second.get().id, 22)
    try expect_equal(value.get().id, 20)
    return ok(unit)

test "callbacks borrow resource inputs while reusable methods copy only retained data":
    let tmp = temporary("wrapper-callback-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()
    try bound_transform(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "21,22,20,")

    let data: String!Int = ok("payload")
    let convert = data.to_optional
    try expect_equal(convert().get(), "payload")
    try expect_equal(convert().get(), "payload")
    try expect_equal(data.get(), "payload")

test "empty and transformed branches do not manufacture retained payloads":
    let absent: Int? = none
    try expect_equal(absent.ok_or("failure").is_error(), true)
    try expect_equal(absent.ok_or_else(fn: "failure").is_error(), true)

    let failed: Int!Int = error(3)
    try expect_equal(failed.map_error(fn cause: cause + 1).is_error(), true)
    try expect_equal(failed.to_optional().is_none(), true)

    let success: Int!Int = ok(5)
    try expect_equal(success.map(fn item: item + 1).get(), 6)
    try expect_equal(success.and_then(fn item: ok(item + 2)).get(), 7)

fn borrowed_error(log: String) Unit!:
    let value = error_result(31, log.clone())
    let absent = value.to_optional()
    try expect_equal(absent.is_none(), true)
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,")
    try expect_equal(value.is_error(), true)
    return ok(unit)

test "discarded owned errors close while borrowed errors stay alive":
    let tmp = temporary("wrapper-errors-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()

    let absent = error_result(30, log.clone()).to_optional()
    try expect_equal(absent.is_none(), true)
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,")
    try borrowed_error(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "30,31,")

fn specialized_optional[T](value: T?, create: fn() Int) T!Int:
    return value.ok_or_else[Int](create)

fn specialized_error[T](value: Int!T) String!T:
    return value.map[String](fn item: "{item}")

fn specialized_transfers(log: String) Unit:
    let present: Marker? = Marker(60, log.clone())
    let _first = specialized_optional(present, fn: 0)
    let failed: Int!Marker = error(Marker(61, log))
    let _second = specialized_error(failed)

test "specialized direct generic methods transfer instead of retaining reusable captures":
    let tmp = temporary("wrapper-specialized-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()
    specialized_transfers(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "61,60,")

type Box:
    items: List[Int]

impl Box:
    fn read[T](_tag: T) List[Int]: self.items

    var fn change[T](_tag: T) Int:
        self.items.append(3)
        return self.items.length()

test "specialized source methods and indexed function calls keep their receiver paths":
    var box = Box([1, 2])
    try expect_equal(box.read[Int](0).length(), 2)
    try expect_equal(box.change[Int](0), 3)
    try expect_equal(box.items, [1, 2, 3])

    let callbacks = [fn(value: Int) Int: value + 1]
    try expect_equal(callbacks[0](4), 5)
