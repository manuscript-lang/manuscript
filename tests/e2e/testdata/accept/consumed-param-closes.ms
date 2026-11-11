import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String

impl Closeable for Door:
	var fn close() Unit!:
		_ := append_file(self.log, "{self.id},").wait()

fn logged(path: String) String:
	read := read_file(path).wait()
	if bytes := read: return bytes.decode_utf8().get("")

	return ""

fn keep_if(d: Door, keep: Bool) Door?:
	if keep: return d
	return none

test "a parameter the callee drops on some path is closed there":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	kept := keep_if(Door(1, log.clone()), true)
	logged(log.clone()) | expect_equal("")?

	dropped := keep_if(Door(2, log.clone()), false)
	logged(log.clone()) | expect_equal("2,")?
	if kept.is_some() and dropped.is_none():
		logged(log.clone()) | expect_equal("2,")?

test "a bound resource passed to such a callee closes once":
	tmp := temporary("ms-log-") | expect_ok?
	log := "{tmp.path()}/log"
	door := Door(3, log.clone())
	dropped := keep_if(door, false)
	logged(log.clone()) | expect_equal("3,")?
	if dropped.is_none():
		logged(log.clone()) | expect_equal("3,")?
