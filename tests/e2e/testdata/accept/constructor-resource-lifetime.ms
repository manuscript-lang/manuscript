import (
	promise from "@std/concurrency/promise.ms",
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
	milliseconds, sleep from "@std/time.ms",
)

type Token:
	log: String
	id: Int
	closed: Bool = false
	fail: Bool = false

fn var Token.close() Unit!:
	if not self.closed:
		self.closed = true
		append_file(self.log, "close {self.id}\n").wait()?
		if self.fail: return error(Error("close failed", kind: "ECLOSE"))

fn token(log: String, id: Int, fail: Bool = false) Token:
	append_file(log, "acquire {id}\n").wait().get()
	return Token(log.clone(), id, fail: fail)

fn events(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")
	return ""

fn check(log: String, action: Int) Int!:
	append_file(log, "check\n").wait()?
	if action == 1: return error(Error("field failed", kind: "EBODY"))

	if action == 2: panic("field fault")
	if action == 3: sleep(milliseconds(60000)).wait()?
	return ok(42)

type Pair:
	first: Token
	second: Token
	code: Int

fn direct(log: String, action: Int) Unit!:
	value := Pair(token(log, 1), token(log, 2), check(log, action)?)
	append_file(log, "body {value.code}\n").wait()?

fn labeled(log: String, action: Int) Unit!:
	value := Pair(
		second: token(log, 2), first: token(log, 1), code: check(log, action)?
	)
	append_file(log, "body {value.code}\n").wait()?

type Wrapped:
	first: Token?
	second: Token!
	code: Int

fn wrapped(log: String, action: Int) Unit!:
	value := Wrapped(token(log, 1), ok(token(log, 2)), check(log, action)?)
	append_file(log, "body {value.code}\n").wait()?

fn default_code(log: String, action: Int) Int:
	append_file(log, "default\n").wait().get()
	if action == 2: panic("default fault")
	return 42

type Defaulted:
	log: String
	first: Token
	action: Int
	second: Token = token(log, 2)
	code: Int = default_code(log, action)

fn defaulted(log: String, action: Int) Unit!:
	value := Defaulted(log.clone(), token(log, 1), action)
	append_file(log, "body {value.code}\n").wait()?

type Nested:
	first: Pair
	last: Token
	code: Int

fn nested(log: String, action: Int) Unit!:
	value := Nested(
		Pair(token(log, 1), token(log, 2), 0), token(log, 3), check(log, action)?
	)
	append_file(log, "body {value.code}\n").wait()?

fn moved_binding(log: String, action: Int) Unit!:
	_outer := token(log, 0)
	first := token(log, 1)
	value := Pair(first, token(log, 2), check(log, action)?)
	append_file(log, "body {value.code}\n").wait()?

fn inspect(first: Token, value: Pair) Int:
	return first.id + value.code

fn outer_temporary(log: String) Int!:
	return ok(
		inspect(
			token(log, 0), Pair(token(log, 1), token(log, 2), check(log, 1)?)
		)
	)

fn failing_cleanup(log: String) Unit!:
	_value := Pair(token(log, 1), token(log, 2, fail: true), check(log, 1)?)

fn wait_for_check(log: String) Unit!:
	for attempt in 0..1000:
		if events(log).contains("check\n"): return ok(unit)

		sleep(milliseconds(1)).wait()?

	return error(Error("constructor handshake timed out", kind: "ETIMEDOUT"))

test "constructed holders own their resource fields on success":
	dir := temporary("constructor-success-") | expect_ok?
	log := "{dir.path()}/events"
	direct(log, 0)?
	expect_equal(
		events(log), "acquire 1\nacquire 2\ncheck\nbody 42\nclose 2\nclose 1\n"
	)?

test "try closes earlier fields before returning its original error":
	dir := temporary("constructor-try-") | expect_ok?
	log := "{dir.path()}/events"
	cause := direct(log, 1) | expect_error?
	expect_equal(cause.kind, "EBODY")?
	expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")?

test "intact Optional and Result constructor fields close on try failure":
	dir := temporary("constructor-wrapper-") | expect_ok?
	log := "{dir.path()}/events"
	cause := wrapped(log, 1) | expect_error?
	expect_equal(cause.kind, "EBODY")?
	expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")?

test "partial construction closes reverse written acquisition order":
	dir := temporary("constructor-label-failure-") | expect_ok?
	log := "{dir.path()}/events"
	_ := labeled(log, 1) | expect_error?
	expect_equal(events(log), "acquire 2\nacquire 1\ncheck\nclose 1\nclose 2\n")?

test "complete construction closes reverse declaration order":
	dir := temporary("constructor-label-success-") | expect_ok?
	log := "{dir.path()}/events"
	labeled(log, 0)?
	expect_equal(
		events(log), "acquire 2\nacquire 1\ncheck\nbody 42\nclose 2\nclose 1\n"
	)?

test "a later field fault closes earlier acquired fields repeatedly":
	dir := temporary("constructor-fault-") | expect_ok?

	for attempt in 0..3:
		log := "{dir.path()}/{attempt}"
		work := promise(fn: direct(log, 2))
		cause := work.wait() | expect_error?
		expect_equal(cause.kind, "EIO")?
		expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")?

test "resource field defaults transfer to the completed holder":
	dir := temporary("constructor-default-success-") | expect_ok?
	log := "{dir.path()}/events"
	defaulted(log, 0)?
	expect_equal(
		events(log), "acquire 1\nacquire 2\ndefault\nbody 42\nclose 2\nclose 1\n"
	)?

test "a faulting default closes both provided and default resources":
	dir := temporary("constructor-default-fault-") | expect_ok?
	log := "{dir.path()}/events"
	work := promise(fn: defaulted(log, 2))
	_ := work.wait() | expect_error?
	expect_equal(events(log), "acquire 1\nacquire 2\ndefault\nclose 2\nclose 1\n")?

test "nested acquired holders close depth first on an error":
	dir := temporary("constructor-nested-") | expect_ok?
	log := "{dir.path()}/events"
	_ := nested(log, 1) | expect_error?
	expect_equal(
		events(log),
		"acquire 1\nacquire 2\nacquire 3\ncheck\nclose 3\nclose 2\nclose 1\n"
	)?

test "moving a prior binding into a partial holder preserves one owner":
	dir := temporary("constructor-move-") | expect_ok?
	log := "{dir.path()}/events"
	work := promise(fn: moved_binding(log, 2))
	_ := work.wait() | expect_error?
	expect_equal(
		events(log),
		"acquire 0\nacquire 1\nacquire 2\ncheck\nclose 2\nclose 1\nclose 0\n"
	)?

test "pending constructor fields close before an older call temporary":
	dir := temporary("constructor-outer-temp-") | expect_ok?
	log := "{dir.path()}/events"
	_ := outer_temporary(log) | expect_error?
	expect_equal(
		events(log),
		"acquire 0\nacquire 1\nacquire 2\ncheck\nclose 2\nclose 1\nclose 0\n"
	)?

test "a temporary close failure faults and still closes other fields":
	dir := temporary("constructor-close-fault-") | expect_ok?
	log := "{dir.path()}/events"
	work := promise(fn: failing_cleanup(log))
	cause := work.wait() | expect_error?
	expect_equal(cause.kind, "EIO")?
	expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")?

test "cancelling a later field closes acquired fields once":
	dir := temporary("constructor-cancel-") | expect_ok?

	for attempt in 0..2:
		log := "{dir.path()}/{attempt}"
		work := promise(fn: direct(log, 3))
		wait_for_check(log)?
		work.cancel()

		cause := work.wait() | expect_error?
		expect_equal(cause.kind, "ECANCELED")?
		expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")?
