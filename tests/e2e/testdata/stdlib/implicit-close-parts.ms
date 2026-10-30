import expect_equal, expect_ok from "@std/test.ms"
import Closeable from "@std/core.ms"
import filesystem from "@std/fs.ms"

# Close appends the id to a log file, so the log is the order in which the closes ran.
type Tracked:
    log: String
    id: Int

impl Closeable for Tracked:
    var fn close() Unit:
        let _ = filesystem().append_file(self.log, "{self.id},")

fn track(log: String, id: Int) Tracked:
    return Tracked(log, id)

fn closed(log: String) String:
    if let bytes = filesystem().read_file(log):
        return bytes.decode_utf8().get("")

    return ""

type Pair:
    first: Tracked
    second: Tracked

type Nested:
    pair: Pair
    all: List[Tracked]

type Slot:
    case Empty
    case Full(item: Tracked)
    case Both(left: Tracked, right: Tracked)

# Closes itself, then the field it owns.
type Wrapper:
    log: String
    inner: Tracked

impl Closeable for Wrapper:
    var fn close() Unit:
        let _ = filesystem().append_file(self.log, "wrapper,")

fn holds_fields(log: String) Int:
    let p = Pair(track(log.clone(), 1), track(log, 2))
    return p.first.id

fn holds_list(log: String) Int:
    let xs = [track(log.clone(), 1), track(log.clone(), 2), track(log, 3)]
    return xs.length()

fn holds_map(log: String) Int:
    var m = Map[String, Tracked]()
    m.add("a", track(log.clone(), 1))
    m.add("b", track(log, 2))
    return m.length()

fn holds_nested(log: String) Int:
    let n = Nested(
        Pair(track(log.clone(), 1), track(log.clone(), 2)),
        [track(log.clone(), 3), track(log, 4)]
    )
    return n.all.length()

fn holds_optional(log: String, present: Bool) Int:
    var _held: Optional[Tracked] = none
    if present:
        _held = some(track(log, 1))
    return 0

fn holds_alternative(log: String) Int:
    let _both = Slot.Both(track(log.clone(), 1), track(log, 2))
    let _empty = Slot.Empty
    return 0

fn holds_wrapper(log: String) Int:
    let w = Wrapper(log.clone(), track(log, 1))
    return w.inner.id

fn returns_early(log: String, early: Bool) Int:
    let p = Pair(track(log.clone(), 1), track(log, 2))
    if early:
        return 1

    return p.first.id

fn moves_on(log: String) Pair:
    let p = Pair(track(log.clone(), 1), track(log, 2))
    return p

test "a record closes its fields, last declared first":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_fields(log.clone()), 1)
    try expect_equal(closed(log), "2,1,")

test "a list closes its elements, last first":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_list(log.clone()), 3)
    try expect_equal(closed(log), "3,2,1,")

test "a map closes its values, last inserted first":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_map(log.clone()), 2)
    try expect_equal(closed(log), "2,1,")

test "nested records and lists close depth first, last first":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_nested(log.clone()), 2)
    try expect_equal(closed(log), "4,3,2,1,")

test "an optional closes the resource it holds":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_optional(log.clone(), true), 0)
    try expect_equal(closed(log.clone()), "1,")

test "an empty optional closes nothing":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_optional(log.clone(), false), 0)
    try expect_equal(closed(log), "")

test "an alternative closes the fields of the case it holds":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_alternative(log.clone()), 0)
    try expect_equal(closed(log), "2,1,")

test "a type's own close runs before the resources it holds":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(holds_wrapper(log.clone()), 1)
    try expect_equal(closed(log), "wrapper,1,")

test "an early return closes the parts":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    try expect_equal(returns_early(log.clone(), true), 1)
    try expect_equal(closed(log), "2,1,")

test "a record handed to the caller is not closed by the callee":
    let temporary = filesystem().temporary("manuscript-parts-") | try expect_ok
    let log = "{temporary.path()}/log"
    let p = moves_on(log.clone())
    try expect_equal(closed(log), "")
    try expect_equal(p.first.id, 1)
