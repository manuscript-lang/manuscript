import expect_equal from "@std/test/test.ms"
import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"
import append_file, remove, temporary_directory, read_file from "@std/os/fs.ms"

type Door:
    name: String
    log: String

impl Closeable for Door:
    var fn close() Unit!:
        try append_file(self.log, "closed " + self.name + ";")
        return ok(unit)

fn size(door: Door) Int!:
    return ok(door.name.length())

fn slow(door: Door) Int!:
    return ok(door.name.length())

test "a promise owns the resource moved into it and closes it when it ends":
    let dir = try temporary_directory("promise-owned")
    let log = dir + "/log"
    let door = Door(name: "front", log: log.clone())
    let p = promise(fn: size(door))
    try expect_equal(try p.wait(), 5)

    let data = try read_file(log, none)
    let text = data.decode_utf8().get("")
    try expect_equal(text, "closed front;")
    try remove(dir, true)

test "a promise dropped before waiting still closes what it owns":
    let dir = try temporary_directory("promise-dropped")
    let log = dir + "/log"

    if true:
        let door = Door(name: "back", log: log.clone())
        let _p = promise(fn: slow(door))

    let data = try read_file(log, none)
    let text = data.decode_utf8().get("")
    try expect_equal(text, "closed back;")
    try remove(dir, true)
