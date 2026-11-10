import (
    expect_equal, expect_fault, expect_contains from "@std/test/test.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
)

test "bound list mutators copy named string inputs without consuming callers":
    var values = ["old"]
    let next = "new-{1}"
    let set = values.set
    set(value: next, index: 0)
    try expect_equal(next, "new-1")

    let append = values.append
    append(next)

    let insert = values.insert
    insert(value: next, index: 1)

    let replace = values.replace
    let old = replace(0, next)
    try expect_equal(old, "new-1")
    try expect_equal(next, "new-1")
    try expect_equal(values, ["new-1", "new-1", "new-1"])

fn fill[T: Clonable](var target: List[T], item: T) Unit:
    let append = target.append
    append(item)
    append(item)

test "generic bound mutator copies aggregate payload storage independently":
    var target: List[List[String]] = []
    var item = ["original-{1}"]
    fill(var target, item)
    item[0] = "changed"
    try expect_equal(target, [["original-1"], ["original-1"]])
    target[0][0] = "first"
    try expect_equal(target[1][0], "original-1")
    try expect_equal(item[0], "changed")

test "optional native adapter handles supplied and absent payloads":
    var values: List[String?] = ["first"]
    let set = values.set
    let text: String? = "next-{2}"
    set(0, text)
    set(0, none)
    set(0, text)
    try expect_equal(values[0], text)
    try expect_equal(text.get(), "next-2")

fn invalid(value: String, index: Int) Unit:
    var values = ["old"]
    let set = values.set
    set(index, value)

test "invalid bound mutation does not consume the caller payload":
    let text = "survives-{3}"
    let fault = try expect_fault(fn: invalid(text, 2))
    try expect_contains(fault, "index")
    try expect_equal(text, "survives-3")

fn supplied(log: String) String!:
    try append_file(log, "value,").wait()
    return ok("supplied")

fn picked(log: String, fail: Bool) Int!:
    try append_file(log, "index,").wait()
    if fail: return error(Error("index failure"))

    return ok(0)

fn ordered(log: String, fail: Bool) List[String]!:
    var values = ["old"]
    let set = values.set
    set(value: try supplied(log), index: try picked(log, fail))
    return ok(values)

test "bound native argument copies preserve named effects and propagation":
    let tmp = try temporary("bound-native-order-")
    let log = "{tmp.path()}/log"
    try expect_equal((try ordered(log, false)), ["supplied"])
    try expect_equal((try read_file(log).wait()).decode_utf8().get(), "value,index,")
    try expect_equal(ordered(log, true).is_error(), true)
    try expect_equal(
        (try read_file(log).wait()).decode_utf8().get(), "value,index,value,index,"
    )

test "nonconsuming bound methods continue borrowing ordinary inputs":
    let values = ["a", "b"]
    let contains = values.contains
    let query = try "b-{1}".slice(0, 1)
    try expect_equal(contains(query), true)
    try expect_equal(query, "b")

test "bound native getter defaults remain unchanged":
    let values = ["first"]
    let get = values.get
    try expect_equal(get(0), "first")

    let fallback = "fallback-{1}"
    try expect_equal(get(2, fallback), fallback)
    try expect_equal(fallback, "fallback-1")
