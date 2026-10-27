# conform: tags=aliasing,closures,control-flow,faults,formatter,interfaces,lists,maps,match,modules,optional,parser,records,stdlib-cleanup,stdlib-json,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/values-cleanup.ms
from "@std/test.ms" import expect_equal, expect_false, expect_not_equal, expect_ok, fail
from "@std/core.ms" import Closeable
from "@std/json.ms" import JsonError
from "@std/fs.ms" import filesystem
from "@std/bytes.ms" import Bytes

type Key:
    id: Int
    label: String

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return self.id == other.id

impl Hashable for Key:
    def hash() -> Int: self.id

type Resource:
    dir: String
    id: Int

# Resources own their state, so close records order through the filesystem:
# resource 1 notes whether resource 2 had already closed.
impl Closeable for Resource:
    var def close() -> Unit:
        let fs = filesystem()
        let inner_closed = fs.read_file(f"{self.dir}/2").is_ok()
        let _ = fs.write_file(f"{self.dir}/{self.id}", f"{inner_closed}", True)

def leave(dir: String) -> Int:
    with let outer = Resource(dir, 1):
        with let inner = Resource(dir, 2):
            return 42

def propagate(result: Result[Int, JsonError]) -> Result[Int, JsonError]:
    let found = try result
    return ok(found + 1)

test "Optional lazy fallbacks preserve nested absence and payload identity":
    let create = lambda: some(42)
    let present: Optional[Int] = some(0)
    let missing: Optional[Int] = none
    try expect_equal(present.or_else(create).get(), 0)
    try expect_equal(missing.or_else(create).get(), 42)

    let nested: Optional[Optional[Int]] = some(missing)
    try expect_false(not nested.is_some() or not nested.get().is_none())

test "Result propagation and Error views preserve concrete causes":
    let failed: Result[Int, JsonError] = error(JsonError.InvalidData)
    try expect_equal(propagate(failed), failed)

    let success: Result[Int, JsonError] = ok(3)
    let expected: Result[Int, JsonError] = ok(4)
    try expect_equal(propagate(success), expected)

    let view = Error(JsonError.InvalidData)
    try expect_not_equal(view.message().byte_length(), 0)

    match view:
        case JsonError(cause):
            try expect_equal(cause, JsonError.InvalidData)
        case _: return fail("error receiver erased")

test "custom equality and hashing define map key identity":
    let first = Key(1, "first")
    let second = Key(1, "second")
    try expect_false(first != second or first.hash() != second.hash())

    var map = Map[Key, String]()
    map.add(first, "a")
    map.add(second, "b")
    try expect_false(map.length() != 1 or map.get(first) != some("b"))

test "Closeable cleanup runs in reverse order before return delivery":
    let fs = filesystem()

    with let temporary = (fs.temporary("manuscript-cleanup-") | try expect_ok):
        let dir = temporary.path()
        try expect_equal(leave(dir), 42)
        try expect_equal((try fs.read_file(f"{dir}/1")), Bytes([116, 114, 117, 101]))
        try expect_equal(
            (try fs.read_file(f"{dir}/2")), Bytes([102, 97, 108, 115, 101])
        )
