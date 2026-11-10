import (
    Closeable from "@std/core.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
    expect_equal, expect_ok from "@std/test/test.ms",
)

type Marker:
    id: Int
    log: String
    closed: Bool = false

impl Closeable for Marker:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()

fn result(id: Int, log: String) Marker!Error: ok(Marker(id, log))

fn optional(id: Int, log: String) Marker?: Marker(id, log)

fn transfer_result_local(log: String) Unit:
    let original = result(1, log)
    let _kept = original.or_else(fn cause: error(cause))

fn transfer_result_temporary(log: String) Unit:
    let _kept = result(2, log).or_else(fn cause: error(cause))

fn transfer_optional_local(log: String) Unit:
    let original = optional(3, log)
    let _kept = original.or_else(fn: none)

fn transfer_optional_temporary(log: String) Unit:
    let _kept = optional(4, log).or_else(fn: none)

test "native wrapper passthrough transfers resources without duplicating owners":
    let tmp = temporary("wrapper-passthrough-") | try expect_ok
    let log = "{tmp.path()}/log"
    transfer_result_local(log.clone())
    transfer_result_temporary(log.clone())
    transfer_optional_local(log.clone())
    transfer_optional_temporary(log.clone())

    let events = read_file(log).wait().get().decode_utf8().get("")
    try expect_equal(events, "1,2,3,4,")

fn recover_resource_error(log: String) Unit!:
    let original: Int!Marker = error(Marker(5, log))
    let recovered = original.or_else(fn cause: ok(cause.id))
    try expect_equal(original.is_error(), true)
    try expect_equal(recovered.get(), 5)

fn bound_resource_error(log: String) Unit!:
    let original: Int!Marker = error(Marker(6, log))
    let recover = original.or_else
    let first = recover(fn cause: ok(cause.id))
    let second = recover(fn cause: ok(cause.id + 1))
    try expect_equal(original.is_error(), true)
    try expect_equal(first.get(), 6)
    try expect_equal(second.get(), 7)

test "or_else only borrows a resource error while preserving copyable successes":
    let tmp = temporary("wrapper-error-borrow-") | try expect_ok
    let log = "{tmp.path()}/log"
    try recover_resource_error(log.clone())
    try bound_resource_error(log.clone())

    let events = read_file(log).wait().get().decode_utf8().get("")
    try expect_equal(events, "5,6,")

fn optional_callback(fail: Bool) (fn() Marker?)!:
    if fail: return error(Error("callback unavailable"))

    return ok(fn: none)

fn result_callback(fail: Bool) (fn(Error) Marker!Error)!:
    if fail: return error(Error("callback unavailable"))

    return ok(fn cause: error(cause))

fn held_result_temporary(id: Int, log: String, fail: Bool) Unit!:
    let _kept = result(id, log).or_else(try result_callback(fail))

fn held_result_local(id: Int, log: String, fail: Bool) Unit!:
    let original = result(id, log)
    let _kept = original.or_else(try result_callback(fail))

fn held_optional_temporary(id: Int, log: String, fail: Bool) Unit!:
    let _kept = optional(id, log).or_else(try optional_callback(fail))

fn held_optional_local(id: Int, log: String, fail: Bool) Unit!:
    let original = optional(id, log)
    let _kept = original.or_else(try optional_callback(fail))

test "owned native receivers stay closeable until later try arguments succeed":
    let tmp = temporary("wrapper-held-receiver-") | try expect_ok
    let log = "{tmp.path()}/log"
    try held_result_temporary(1, log.clone(), false)
    try held_result_local(2, log.clone(), false)
    try held_optional_temporary(3, log.clone(), false)
    try held_optional_local(4, log.clone(), false)
    try expect_equal(held_result_temporary(5, log.clone(), true).is_error(), true)
    try expect_equal(held_result_local(6, log.clone(), true).is_error(), true)
    try expect_equal(held_optional_temporary(7, log.clone(), true).is_error(), true)
    try expect_equal(held_optional_local(8, log.clone(), true).is_error(), true)

    let events = read_file(log).wait().get().decode_utf8().get("")
    try expect_equal(events, "1,2,3,4,5,6,7,8,")

fn borrowed_error_callback(fail: Bool) (fn(Marker) Int!Marker)!:
    if fail: return error(Error("callback unavailable"))

    return ok(fn cause: ok(cause.id))

fn borrowed_error_before_try(id: Int, log: String, fail: Bool) Unit!:
    let original: Int!Marker = error(Marker(id, log))
    let recovered = original.or_else(try borrowed_error_callback(fail))
    try expect_equal(original.is_error(), true)
    try expect_equal(recovered.get(), id)

test "later try does not take ownership of a genuinely borrowed native receiver":
    let tmp = temporary("wrapper-borrowed-receiver-") | try expect_ok
    let log = "{tmp.path()}/log"
    try borrowed_error_before_try(9, log.clone(), false)
    try expect_equal(borrowed_error_before_try(10, log.clone(), true).is_error(), true)

    let events = read_file(log).wait().get().decode_utf8().get("")
    try expect_equal(events, "9,10,")
