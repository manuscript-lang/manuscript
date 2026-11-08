import Closeable from "@std/core.ms"
import append_file, read_file, temporary, write_file from "@std/os/fs.ms"
import expect_equal, expect_some from "@std/test/test.ms"

type Resource:
    id: Int
    path: String

impl Closeable for Resource:
    var fn close() Unit!:
        try append_file(self.path, "{self.id},").wait()
        return ok(unit)

fn accepted() Int!: ok(1)

fn failing() Int!: error(Error("stop"))

fn observed(value: Resource?, tail: Int = try accepted()) Bool!:
    return ok(value.is_some() or tail > 0)

fn refused(value: Resource?, tail: Int = try failing()) Bool!:
    return ok(value.is_some() or tail > 0)

fn log_text(path: String) String!:
    let bytes = try read_file(path).wait()
    return ok(try expect_some(bytes.decode_utf8()))

test "a temporary passed to a call with a fallible default closes once":
    let directory = try temporary("fallible-default-")
    let path = "{directory.path()}/log"
    try write_file(path, "").wait()
    try expect_equal(try observed(Resource(3, path.clone())), true)
    try expect_equal(try log_text(path), "3,")

test "a temporary closes when the fallible default fails":
    let directory = try temporary("fallible-default-fails-")
    let path = "{directory.path()}/log"
    try write_file(path, "").wait()
    try expect_equal(refused(Resource(4, path.clone())).is_error(), true)
    try expect_equal(try log_text(path), "4,")

test "a named resource lent to a call with a fallible default is not closed early":
    let directory = try temporary("fallible-default-named-")
    let path = "{directory.path()}/log"
    try write_file(path, "").wait()

    let named = Resource(5, path.clone())
    try expect_equal(try observed(named), true)
    try expect_equal(try log_text(path), "")
    try expect_equal(named.id, 5)
