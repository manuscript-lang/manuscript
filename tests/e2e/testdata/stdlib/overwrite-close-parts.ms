from "@std/test.ms" import expect_equal, expect_ok
from "@std/core.ms" import Closeable
from "@std/fs.ms" import filesystem

# Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
    log: String
    id: Int

impl Closeable for Tracked:
    var def close() -> Unit:
        let _ = filesystem().append_file(self.log, f"{self.id},")

def track(log: String, id: Int) -> Tracked:
    return Tracked(log, id)

def closed(log: String) -> String:
    if let bytes = filesystem().read_file(log):
        return bytes.decode_utf8().get("")

    return ""

type Pair:
    first: Tracked
    second: Tracked

def replaces_field(log: String) -> Int:
    var p = Pair(track(log.clone(), 1), track(log.clone(), 2))
    p.first = track(log, 3)
    return p.first.id

def replaces_element(log: String) -> Int:
    var xs = [track(log.clone(), 1), track(log.clone(), 2)]
    xs.set(0, track(log, 3))
    return xs.length()

def replaces_from_end(log: String) -> Int:
    var xs = [track(log.clone(), 1), track(log.clone(), 2)]
    xs.set(-1, track(log, 3))
    return xs.length()

def removes_element(log: String) -> Int:
    var xs = [track(log.clone(), 1), track(log.clone(), 2), track(log, 3)]
    xs.remove(1)
    return xs.length()

test "overwriting a field closes the old value first":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(replaces_field(log.clone()), 3)
    try expect_equal(closed(log), "1,2,3,")

test "set closes the element it replaces":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(replaces_element(log.clone()), 2)
    try expect_equal(closed(log), "1,2,3,")

test "set with a negative index closes the element counted from the end":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(replaces_from_end(log.clone()), 2)
    try expect_equal(closed(log), "2,3,1,")

test "remove closes the element it drops":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(removes_element(log.clone()), 2)
    try expect_equal(closed(log), "2,3,1,")

def replaces_map_value(log: String) -> Int:
    var m = Map[String, Tracked]()
    m.add("a", track(log.clone(), 1))
    m.add("b", track(log.clone(), 2))
    m.add("a", track(log, 3))
    return m.length()

def adds_new_map_key(log: String) -> Int:
    var m = Map[String, Tracked]()
    m.add("a", track(log.clone(), 1))
    m.add("b", track(log, 2))
    return m.length()

def removes_map_value(log: String) -> Int:
    var m = Map[String, Tracked]()
    m.add("a", track(log.clone(), 1))
    m.add("b", track(log, 2))
    m.remove("a")
    m.remove("missing")
    return m.length()

def clears_map(log: String) -> Int:
    var m = Map[String, Tracked]()
    m.add("a", track(log.clone(), 1))
    m.add("b", track(log, 2))
    m.clear()
    return m.length()

test "add over an existing key closes the old value":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(replaces_map_value(log.clone()), 2)
    try expect_equal(closed(log), "1,2,3,")

test "add under a new key closes nothing until the scope ends":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(adds_new_map_key(log.clone()), 2)
    try expect_equal(closed(log), "2,1,")

test "remove closes the value it drops":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(removes_map_value(log.clone()), 1)
    try expect_equal(closed(log), "1,2,")

test "clear closes every value, last inserted first":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(clears_map(log.clone()), 0)
    try expect_equal(closed(log), "2,1,")

def splices_elements(log: String) -> Int:
    var xs = [
        track(log.clone(), 1), track(log.clone(), 2), track(log.clone(), 3),
        track(log.clone(), 4)
    ]
    xs.splice(1, 2, [track(log, 5)])
    return xs.length()

def pops_into_ignored(log: String) -> Int:
    var xs = [track(log.clone(), 1), track(log, 2)]
    let _last = xs.pop()
    return xs.length()

test "splice closes the deleted elements, last first":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(splices_elements(log.clone()), 3)
    try expect_equal(closed(log), "3,2,4,5,1,")

test "a popped value bound to an ignored name closes at scope end":
    let temporary = filesystem().temporary("manuscript-overwrite-") | try expect_ok
    let log = f"{temporary.path()}/log"
    try expect_equal(pops_into_ignored(log.clone()), 1)
    try expect_equal(closed(log), "2,1,")
