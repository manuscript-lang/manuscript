import expect_equal from "@std/test/test.ms"
import promise from "@std/concurrency/promise.ms"
import Closeable from "@std/core.ms"
import append_file, remove, temporary_directory, read_file from "@std/os/fs.ms"

type Door:
    name: String
    log: String

impl Closeable for Door:
    var fn close() Unit!:
        try append_file(self.log, "closed " + self.name + ";").wait()
        return ok(unit)

fn size(door: Door) Int!:
    return ok(door.name.length())

fn slow(door: Door) Int!:
    return ok(door.name.length())

test "a promise owns the resource moved into it and closes it when it ends":
    dir := try temporary_directory("promise-owned")
    log := dir + "/log"
    door := Door(name: "front", log: log.clone())
    p := promise(fn: size(door))
    try expect_equal(try p.wait(), 5)

    data := try read_file(log, none).wait()
    text := data.decode_utf8().get("")
    try expect_equal(text, "closed front;")
    try remove(dir, true)

test "a promise dropped before waiting still closes what it owns":
    dir := try temporary_directory("promise-dropped")
    log := dir + "/log"

    if true:
        door := Door(name: "back", log: log.clone())
        _p := promise(fn: slow(door))

    data := try read_file(log, none).wait()
    text := data.decode_utf8().get("")
    try expect_equal(text, "closed back;")
    try remove(dir, true)
