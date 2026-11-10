import (
    Closeable, panic from "@std/core.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
    promise from "@std/concurrency/promise.ms",
    milliseconds, sleep from "@std/time.ms",
    expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

type Token:
    log: String
    id: Int
    closed: Bool = false
    fail: Bool = false

impl Closeable for Token:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "close {self.id}\n").wait()
            if self.fail: return error(Error("close failed", kind: "ECLOSE"))

        return ok(unit)

fn token(log: String, id: Int, fail: Bool = false) Token:
    append_file(log, "acquire {id}\n").wait().get()
    return Token(log.clone(), id, fail: fail)

fn events(log: String) String:
    if let bytes = read_file(log).wait(): return bytes.decode_utf8().get("")

    return ""

fn check(log: String, action: Int) Int!:
    try append_file(log, "check\n").wait()
    if action == 1: return error(Error("field failed", kind: "EBODY"))

    if action == 2: panic("field fault")
    if action == 3: try sleep(milliseconds(60000)).wait()
    return ok(42)

type Pair:
    first: Token
    second: Token
    code: Int

fn direct(log: String, action: Int) Unit!:
    let value = Pair(token(log, 1), token(log, 2), try check(log, action))
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

fn labeled(log: String, action: Int) Unit!:
    let value = Pair(
        second: token(log, 2), first: token(log, 1), code: try check(log, action)
    )
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

type Wrapped:
    first: Token?
    second: Token!
    code: Int

fn wrapped(log: String, action: Int) Unit!:
    let value = Wrapped(token(log, 1), ok(token(log, 2)), try check(log, action))
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

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
    let value = Defaulted(log.clone(), token(log, 1), action)
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

type Nested:
    first: Pair
    last: Token
    code: Int

fn nested(log: String, action: Int) Unit!:
    let value = Nested(
        Pair(token(log, 1), token(log, 2), 0), token(log, 3), try check(log, action)
    )
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

fn moved_binding(log: String, action: Int) Unit!:
    let _outer = token(log, 0)
    let first = token(log, 1)
    let value = Pair(first, token(log, 2), try check(log, action))
    try append_file(log, "body {value.code}\n").wait()
    return ok(unit)

fn inspect(first: Token, value: Pair) Int:
    return first.id + value.code

fn outer_temporary(log: String) Int!:
    return ok(
        inspect(
            token(log, 0), Pair(token(log, 1), token(log, 2), try check(log, 1))
        )
    )

fn failing_cleanup(log: String) Unit!:
    let _value = Pair(token(log, 1), token(log, 2, fail: true), try check(log, 1))
    return ok(unit)

fn wait_for_check(log: String) Unit!:
    for attempt in 0..1000:
        if events(log).contains("check\n"): return ok(unit)

        try sleep(milliseconds(1)).wait()

    return error(Error("constructor handshake timed out", kind: "ETIMEDOUT"))

test "constructed holders own their resource fields on success":
    let dir = temporary("constructor-success-") | try expect_ok
    let log = "{dir.path()}/events"
    try direct(log, 0)
    try expect_equal(
        events(log), "acquire 1\nacquire 2\ncheck\nbody 42\nclose 2\nclose 1\n"
    )

test "try closes earlier fields before returning its original error":
    let dir = temporary("constructor-try-") | try expect_ok
    let log = "{dir.path()}/events"
    let cause = direct(log, 1) | try expect_error
    try expect_equal(cause.kind, "EBODY")
    try expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")

test "intact Optional and Result constructor fields close on try failure":
    let dir = temporary("constructor-wrapper-") | try expect_ok
    let log = "{dir.path()}/events"
    let cause = wrapped(log, 1) | try expect_error
    try expect_equal(cause.kind, "EBODY")
    try expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")

test "partial construction closes reverse written acquisition order":
    let dir = temporary("constructor-label-failure-") | try expect_ok
    let log = "{dir.path()}/events"
    let _ = labeled(log, 1) | try expect_error
    try expect_equal(events(log), "acquire 2\nacquire 1\ncheck\nclose 1\nclose 2\n")

test "complete construction closes reverse declaration order":
    let dir = temporary("constructor-label-success-") | try expect_ok
    let log = "{dir.path()}/events"
    try labeled(log, 0)
    try expect_equal(
        events(log), "acquire 2\nacquire 1\ncheck\nbody 42\nclose 2\nclose 1\n"
    )

test "a later field fault closes earlier acquired fields repeatedly":
    let dir = temporary("constructor-fault-") | try expect_ok

    for attempt in 0..3:
        let log = "{dir.path()}/{attempt}"
        let work = promise(fn: direct(log, 2))
        let cause = work.wait() | try expect_error
        try expect_equal(cause.kind, "EIO")
        try expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")

test "resource field defaults transfer to the completed holder":
    let dir = temporary("constructor-default-success-") | try expect_ok
    let log = "{dir.path()}/events"
    try defaulted(log, 0)
    try expect_equal(
        events(log), "acquire 1\nacquire 2\ndefault\nbody 42\nclose 2\nclose 1\n"
    )

test "a faulting default closes both provided and default resources":
    let dir = temporary("constructor-default-fault-") | try expect_ok
    let log = "{dir.path()}/events"
    let work = promise(fn: defaulted(log, 2))
    let _ = work.wait() | try expect_error
    try expect_equal(events(log), "acquire 1\nacquire 2\ndefault\nclose 2\nclose 1\n")

test "nested acquired holders close depth first on an error":
    let dir = temporary("constructor-nested-") | try expect_ok
    let log = "{dir.path()}/events"
    let _ = nested(log, 1) | try expect_error
    try expect_equal(
        events(log),
        "acquire 1\nacquire 2\nacquire 3\ncheck\nclose 3\nclose 2\nclose 1\n"
    )

test "moving a prior binding into a partial holder preserves one owner":
    let dir = temporary("constructor-move-") | try expect_ok
    let log = "{dir.path()}/events"
    let work = promise(fn: moved_binding(log, 2))
    let _ = work.wait() | try expect_error
    try expect_equal(
        events(log),
        "acquire 0\nacquire 1\nacquire 2\ncheck\nclose 2\nclose 1\nclose 0\n"
    )

test "pending constructor fields close before an older call temporary":
    let dir = temporary("constructor-outer-temp-") | try expect_ok
    let log = "{dir.path()}/events"
    let _ = outer_temporary(log) | try expect_error
    try expect_equal(
        events(log),
        "acquire 0\nacquire 1\nacquire 2\ncheck\nclose 2\nclose 1\nclose 0\n"
    )

test "a temporary close failure faults and still closes other fields":
    let dir = temporary("constructor-close-fault-") | try expect_ok
    let log = "{dir.path()}/events"
    let work = promise(fn: failing_cleanup(log))
    let cause = work.wait() | try expect_error
    try expect_equal(cause.kind, "EIO")
    try expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")

test "cancelling a later field closes acquired fields once":
    let dir = temporary("constructor-cancel-") | try expect_ok

    for attempt in 0..2:
        let log = "{dir.path()}/{attempt}"
        let work = promise(fn: direct(log, 3))
        try wait_for_check(log)
        work.cancel()

        let cause = work.wait() | try expect_error
        try expect_equal(cause.kind, "ECANCELED")
        try expect_equal(events(log), "acquire 1\nacquire 2\ncheck\nclose 2\nclose 1\n")
