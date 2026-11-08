import Closeable from "@std/core.ms"
import append_file, read_file, temporary, write_file from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type TextOwner:
    text: String
    log: String
    id: Int

impl Closeable for TextOwner:
    var fn close() Unit!:
        try append_file(self.log, "{self.id},").wait()
        self.text = "closed"
        return ok(unit)

impl TextOwner:
    fn read() String: self.text

    fn read_default(_tag: Int = 0) String: self.text

fn owner(id: Int, log: String) TextOwner:
    return TextOwner("payload-{id}", log, id)

fn ordinary(log: String) String:
    let read = owner(1, log).read
    return read()

fn defaulted(log: String) String:
    let read = owner(2, log).read_default
    return read()

fn explicit_default(log: String) String:
    let read = owner(3, log).read_default
    return read(9)

fn repeated(log: String) List[String]:
    let read = owner(4, log).read
    let first = read()
    let second = read()
    return [first, second]

fn repeated_default(log: String) List[String]:
    let read = owner(5, log).read_default
    let first = read()
    let second = read(7)
    return [first, second]

test "borrowed String method results outlive their owning source environments":
    let tmp = temporary("source-capture-string-") | try expect_ok
    let log = "{tmp.path()}/log"
    try write_file(log, "").wait()

    let first = ordinary(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")
    try expect_equal(first, "payload-1")

    let second = defaulted(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,")
    try expect_equal(second, "payload-2")

    let third = explicit_default(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,")
    try expect_equal(third, "payload-3")

    let fourth = repeated(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,")
    try expect_equal(fourth, ["payload-4", "payload-4"])

    let fifth = repeated_default(log.clone())
    try expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,5,")
    try expect_equal(fifth, ["payload-5", "payload-5"])
