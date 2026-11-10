import (
    Closeable from "@std/core.ms",
    append_file, read_file, temporary, write_file from "@std/os/fs.ms",
    expect_equal, expect_some from "@std/test/test.ms",
)

type Resource:
    id: Int
    path: String

impl Closeable for Resource:
    var fn close() Unit!:
        try append_file(self.path, "{self.id},").wait()

fn accepted() Int!: ok(1)

fn failing() Int!: error(Error("stop"))

fn observed(value: Resource?, tail: Int = try accepted()) Bool!:
    return ok(value.is_some() or tail > 0)

fn refused(value: Resource?, tail: Int = try failing()) Bool!:
    return ok(value.is_some() or tail > 0)

fn log_text(path: String) String!:
    bytes := try read_file(path).wait()
    return ok(try expect_some(bytes.decode_utf8()))

test "a temporary passed to a call with a fallible default closes once":
    directory := try temporary("fallible-default-")
    path := "{directory.path()}/log"
    try write_file(path, "").wait()
    try expect_equal(try observed(Resource(3, path.clone())), true)
    try expect_equal(try log_text(path), "3,")

test "a temporary closes when the fallible default fails":
    directory := try temporary("fallible-default-fails-")
    path := "{directory.path()}/log"
    try write_file(path, "").wait()
    try expect_equal(refused(Resource(4, path.clone())).is_error(), true)
    try expect_equal(try log_text(path), "4,")

test "a named resource lent to a call with a fallible default is not closed early":
    directory := try temporary("fallible-default-named-")
    path := "{directory.path()}/log"
    try write_file(path, "").wait()

    named := Resource(5, path.clone())
    try expect_equal(try observed(named), true)
    try expect_equal(try log_text(path), "")
    try expect_equal(named.id, 5)
