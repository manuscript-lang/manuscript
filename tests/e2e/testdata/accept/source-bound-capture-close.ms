import Closeable from "@std/core.ms"
import append_file, read_file, temporary, write_file from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Marker:
    id: Int
    log: String
    closed: Bool = false

impl Closeable for Marker:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "{self.id},").wait()

        return ok(unit)

impl Marker:
    fn status() Int: self.id

    fn with_default(offset: Int = 10) Int: self.id + offset

    fn generic[T](_value: T) Int: self.id

    var fn bump(delta: Int = 1) Int:
        self.id += delta
        return self.id

fn marker(id: Int, log: String) Marker: Marker(id, log)

fn ordinary(log: String) Unit!:
    status := marker(1, log).status
    try expect_equal(status(), 1)
    try expect_equal(status(), 1)
    return ok(unit)

fn defaulted(log: String) Unit!:
    status := marker(2, log).with_default
    try expect_equal(status(), 12)
    try expect_equal(status(20), 22)
    return ok(unit)

fn generic(log: String) Unit!:
    status := marker(3, log).generic[Int]
    try expect_equal(status(10), 3)
    try expect_equal(status(20), 3)
    return ok(unit)

fn escaped(log: String) fn() Int:
    value := marker(4, log)
    return value.status

fn escaping(log: String) Unit!:
    status := escaped(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,")
    try expect_equal(status(), 4)
    try expect_equal(status(), 4)
    return ok(unit)

fn borrow(value: Marker) Unit!:
    status := value.status
    with_default := value.with_default
    try expect_equal(status(), 5)
    try expect_equal(with_default(), 15)
    return ok(unit)

fn borrowed(log: String) Unit!:
    value := marker(5, log.clone())
    try borrow(value)
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,")
    try expect_equal(value.status(), 5)
    return ok(unit)

test "nonmutating source default and generic method captures close their owners":
    tmp := temporary("source-bound-close-") | try expect_ok
    log := "{tmp.path()}/log"
    try write_file(log, "").wait()
    try ordinary(log.clone())
    try defaulted(log.clone())
    try generic(log.clone())
    try escaping(log.clone())
    try borrowed(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,5,")

fn shared_default(var value: Marker) Unit!:
    bump := value.bump
    try expect_equal(bump(), 8)
    try expect_equal(bump(2), 10)
    return ok(unit)

fn shared_owner(log: String) Unit!:
    var value = marker(7, log.clone())
    try shared_default(var value)
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "")
    try expect_equal(value.status(), 10)
    return ok(unit)

test "shared source default method captures do not close the borrowed receiver":
    tmp := temporary("source-bound-shared-") | try expect_ok
    log := "{tmp.path()}/log"
    try write_file(log, "").wait()
    try shared_owner(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "10,")
