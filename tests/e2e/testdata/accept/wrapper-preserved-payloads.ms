import Closeable from "@std/core.ms"
import append_file, read_file, temporary, write_file from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

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
