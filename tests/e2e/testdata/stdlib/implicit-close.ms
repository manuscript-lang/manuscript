from "@std/test.ms" import expect_equal, expect_false, expect_ok, expect_true
from "@std/core.ms" import Closeable, TextError
from "@std/fs.ms" import filesystem

type Resource:
    dir: String
    id: Int

# Close records itself by writing a marker file named after the resource.
impl Closeable for Resource:
    var def close() -> Unit:
        let _ = filesystem().write_file(f"{self.dir}/{self.id}", "closed", True)

def closed(dir: String, id: Int) -> Bool:
    return filesystem().read_file(f"{dir}/{id}").is_ok()

def falls_off_the_end(dir: String) -> Int:
    let r = Resource(dir, 1)
    return r.id

def returns_early(dir: String, early: Bool) -> Int:
    let r = Resource(dir, 2)
    if early:
        return 1

    return r.id

def propagates(dir: String) -> Result[Int, TextError]:
    let r = Resource(dir, 3)
    let failed: Result[Int, TextError] = error(TextError("boom"))
    let v = try failed
    return ok(v + r.id)

def breaks_out(dir: String) -> Int:
    var i = 0

    while i < 3:
        let r = Resource(dir.clone(), 10 + i)
        i += 1
        if i == 2:
            break
        if r.id == 10:
            continue

    return i

def closes_by_hand_too(dir: String) -> Int:
    var r = Resource(dir, 20)
    r.close()
    return r.id

test "a resource nothing takes is closed when its scope ends":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let dir = temporary.path()
        try expect_equal(falls_off_the_end(dir.clone()), 1)
        try expect_true(closed(dir, 1))
        try expect_equal(returns_early(dir.clone(), True), 1)
        try expect_true(closed(dir, 2))

test "an error leaving the scope still closes it":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let dir = temporary.path()
        try expect_true(propagates(dir.clone()).is_error())
        try expect_true(closed(dir, 3))

test "break and continue close the iteration's resource":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let dir = temporary.path()
        try expect_equal(breaks_out(dir.clone()), 2)
        try expect_true(closed(dir, 10))
        try expect_true(closed(dir, 11))
        try expect_false(closed(dir, 12))

test "closing by hand does not stop the scope's own close":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let dir = temporary.path()
        try expect_equal(closes_by_hand_too(dir.clone()), 20)
        try expect_true(closed(dir, 20))

def reassigns(dir: String) -> Int:
    var r = Resource(dir.clone(), 30)
    r = Resource(dir, 31)
    return r.id

test "reassigning a resource closes the value it replaces":
    with let temporary = filesystem().temporary("manuscript-implicit-") | try expect_ok:
        let dir = temporary.path()
        try expect_equal(reassigns(dir.clone()), 31)
        try expect_true(closed(dir, 30))
        try expect_true(closed(dir, 31))
