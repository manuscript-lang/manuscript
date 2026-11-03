import expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms"
import Closeable from "@std/core.ms"
import read_file, temporary, write_file from "@std/os/fs.ms"

type Resource:
    dir: String
    id: Int

# Close records itself by writing a marker file named after the resource.
impl Closeable for Resource:
    var fn close() Unit!:
        let _ = write_file("{self.dir}/{self.id}", "closed", true)
        return ok(unit)

fn closed(dir: String, id: Int) Bool:
    return read_file("{dir}/{id}").is_ok()

fn falls_off_the_end(dir: String) Int:
    let r = Resource(dir, 1)
    return r.id

fn returns_early(dir: String, early: Bool) Int:
    let r = Resource(dir, 2)
    if early:
        return 1

    return r.id

fn propagates(dir: String) Int!Error:
    let r = Resource(dir, 3)
    let failed: Int!Error = error(Error("boom"))
    let v = try failed
    return ok(v + r.id)

fn breaks_out(dir: String) Int:
    var i = 0

    while i < 3:
        let r = Resource(dir.clone(), 10 + i)
        i += 1
        if i == 2:
            break
        if r.id == 10:
            continue

    return i

fn closes_by_hand_too(dir: String) Int:
    var r = Resource(dir, 20)
    r.close().get(none)
    return r.id

test "a resource nothing takes is closed when its scope ends":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(falls_off_the_end(dir.clone()), 1)
    try expect_true(closed(dir, 1))
    try expect_equal(returns_early(dir.clone(), true), 1)
    try expect_true(closed(dir, 2))

test "an error leaving the scope still closes it":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_true(propagates(dir.clone()).is_error())
    try expect_true(closed(dir, 3))

test "break and continue close the iteration's resource":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(breaks_out(dir.clone()), 2)
    try expect_true(closed(dir, 10))
    try expect_true(closed(dir, 11))
    try expect_false(closed(dir, 12))

test "closing by hand does not stop the scope's own close":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(closes_by_hand_too(dir.clone()), 20)
    try expect_true(closed(dir, 20))

fn reassigns(dir: String) Int:
    var r = Resource(dir.clone(), 30)
    r = Resource(dir, 31)
    return r.id

test "reassigning a resource closes the value it replaces":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(reassigns(dir.clone()), 31)
    try expect_true(closed(dir, 30))
    try expect_true(closed(dir, 31))

fn open_resource(dir: String, id: Int) Resource:
    return Resource(dir, id)

fn temporary_id(dir: String) Int:
    return open_resource(dir, 40).id

test "an unbound resource temporary is closed at the end of its statement":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(temporary_id(dir.clone()), 40)
    try expect_true(closed(dir, 40))

fn pops_and_discards(dir: String) Int:
    var rs = [Resource(dir.clone(), 50), Resource(dir, 51)]
    rs.pop()
    return rs.length()

test "a discarded resource result is closed":
    let temporary = temporary("manuscript-implicit-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(pops_and_discards(dir.clone()), 1)
    try expect_true(closed(dir, 51))
