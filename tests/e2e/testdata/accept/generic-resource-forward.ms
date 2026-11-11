import (
	Closeable, Iterator from "@std/core.ms",
	Source from "@std/io/io.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type Token:
	log: String
	id: Int

fn var Token.close() Unit!:
	append_file(self.log, "close {self.id}\n").wait()?

type Tokens:
	log: String
	at: Int = 0

fn var Tokens.next() Token?!:
	self.at += 1
	if self.at <= 2: return ok(Token(self.log.clone(), self.at))

	return ok(none)

fn var Tokens.close() Unit!:
	return ok(unit)

type Forward[T]:
	source: Source[T]

fn var Forward[T].next() T!?:
	result := self.source.next()
	if result.is_error(): return error(result.err())
	if item := result.get(): return ok(item)

	return none

fn first_body(log: String) Unit!:
	for item in Forward[Token](Tokens(log.clone())):
		token := item?
		append_file(log, "body {token.id}\n").wait()?
		break

fn events(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

test "a generic adapter forwards a resource through Result.get once":
	dir := temporary("generic-forward-") | expect_ok?
	log := "{dir.path()}/events"
	first_body(log.clone())?
	expect_equal(events(log), "body 1\nclose 1\n")?
