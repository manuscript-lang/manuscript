import (
    Closeable from "@std/core.ms",
    append_file, read_file, temporary, write_file from "@std/os/fs.ms",
    expect_equal from "@std/test/test.ms",
)

type Resource:
    path: String

impl Closeable for Resource:
    var fn close() Unit!:
        try append_file(self.path, "closed,").wait()

fn observed(value: Resource?) Bool: value.is_some()

fn use_named(path: String) Unit!:
    named := Resource(path.clone())
    try expect_equal(observed(named), true)

    bytes := try read_file(path).wait()
    try expect_equal(bytes.decode_utf8().get(""), "")

// A named resource borrowed through an implicit Optional stays open; its owner closes it once.
test "borrowing through an Optional does not close the named owner":
    directory := try temporary("optional-borrow-")
    path := "{directory.path()}/log"
    try write_file(path, "").wait()
    try use_named(path.clone())

    bytes := try read_file(path).wait()
    try expect_equal(bytes.decode_utf8().get(""), "closed,")
