// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Door:
	id Int
	log String

fn move Door.close() Void!:
	void append_file(self.log, f"{self.id},").wait()

fn logged(path String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8() or ""

	return ""

fn keep_if(d Door, keep Bool) Door?:
	if keep: return d
	return null

test "a parameter the callee drops on some path is closed there":
	tmp := temporary("ms-log-") | expect_ok?
	log := f"{tmp.path()}/log"
	kept := keep_if(Door(1, log.clone()), true)
	logged(log.clone()) | expect_equal("")?

	dropped := keep_if(Door(2, log.clone()), false)
	logged(log.clone()) | expect_equal("2,")?
	if (kept != null) and (dropped == null):
		logged(log.clone()) | expect_equal("2,")?

test "a bound resource passed to such a callee closes once":
	tmp := temporary("ms-log-") | expect_ok?
	log := f"{tmp.path()}/log"
	door := Door(3, log.clone())
	dropped := keep_if(door, false)
	logged(log.clone()) | expect_equal("3,")?
	if dropped == null:
		logged(log.clone()) | expect_equal("3,")?
