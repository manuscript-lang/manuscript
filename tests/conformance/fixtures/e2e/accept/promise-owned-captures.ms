// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	append_file, read_file, remove, temporary_directory from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Door:
	name: String
	log: String

fn var Door.close() Unit!:
	append_file(self.log, "closed " + self.name + ";").wait()?

fn size(door: Door) Int!:
	return ok(door.name.length())

fn slow(door: Door) Int!:
	return ok(door.name.length())

test "a promise owns the resource moved into it and closes it when it ends":
	dir := temporary_directory("promise-owned")?
	log := dir + "/log"
	door := Door(name: "front", log: log.clone())
	p := promise(fn: size(door))
	expect_equal(p.wait()?, 5)?

	data := read_file(log, none).wait()?
	text := data.decode_utf8().get("")
	expect_equal(text, "closed front;")?
	remove(dir, true)?

test "a promise dropped before waiting still closes what it owns":
	dir := temporary_directory("promise-dropped")?
	log := dir + "/log"

	if true:
		door := Door(name: "back", log: log.clone())
		_p := promise(fn: slow(door))

	data := read_file(log, none).wait()?
	text := data.decode_utf8().get("")
	expect_equal(text, "closed back;")?
	remove(dir, true)?
