// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	Closeable from "@std/core.ms",
	append_file, read_file, remove, temporary_directory from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

type Door {
	name String
	log String
}

fn move Door.close() Void! {
	append_file(self.log, "closed " + self.name + ";").wait()?
}

fn size(door Door) Int! {
	return ok(door.name.length())
}

fn slow(door Door) Int! {
	return ok(door.name.length())
}

fn run_with_door(log String) Int! {
	door := Door(name: "front", log: log.clone())
	p := promise(() => size(door))
	return p.wait()
}

test "a promise that stays in its function reads the resource in place, and the scope closes it" {
	dir := temporary_directory("promise-owned")?
	log := dir + "/log"
	expect_equal(run_with_door(log.clone())?, 5)?

	data := read_file(log, null).wait()?
	text := data.decode_utf8() or ""
	expect_equal(text, "closed front;")?
	remove(dir, true)?
}

test "a promise dropped before waiting leaves the resource to its scope" {
	dir := temporary_directory("promise-dropped")?
	log := dir + "/log"

	if true {
		door := Door(name: "back", log: log.clone())
		_p := promise(() => slow(door))
	}

	data := read_file(log, null).wait()?
	text := data.decode_utf8() or ""
	expect_equal(text, "closed back;")?
	remove(dir, true)?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
