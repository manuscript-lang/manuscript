import (
    Closeable from "@std/core.ms",
    append_file, read_file, remove, temporary_root from "@std/os/fs.ms",
    secure_int from "@std/random.ms",
    expect_equal from "@std/test/test.ms",
)

// A resource with only scalar fields has no drop glue but still has one owner that closes it. Its
// id names the file the close appends to, since it has nowhere to keep a log path.
type Tag:
    id: Int

// The host temp root, since a hard-coded /tmp does not exist on Windows.
fn tag_log(id: Int) String!:
    return ok("{try temporary_root()}/ms-result-get-tag-{id}")

impl Closeable for Tag:
    var fn close() Unit!:
        try append_file(try tag_log(self.id), "closed,").wait()
        return ok(unit)

fn success(id: Int) Tag!Int:
    return ok(Tag(id))

fn events(log: String) String:
    return read_file(log).wait().get().decode_utf8().get("")

fn project(id: Int) Int:
    return success(id).get().id

test "a projection of a scalar resource taken from a Result closes it once":
    let id = try secure_int(1, 1000000000)
    let log = try tag_log(id)
    try expect_equal(project(id), id)
    try expect_equal(events(log.clone()), "closed,")
    try remove(log)
