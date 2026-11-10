import (
    Closeable, Iterator from "@std/core.ms",
    ReadStream, Source from "@std/io/io.ms",
    promise from "@std/concurrency/promise.ms",
    milliseconds, sleep from "@std/time.ms",
    append_file, read_file, temporary from "@std/os/fs.ms",
    expect_equal, expect_ok, expect_error from "@std/test/test.ms",
)

type Token:
    id: Int
    log: String
    closed: Bool = false

impl Closeable for Token:
    var fn close() Unit!:
        if not self.closed:
            self.closed = true
            try append_file(self.log, "close {self.id}\n").wait()

type Tokens:
    log: String
    at: Int = 0
    fail_at: Int = 0

impl Source[Token] for Tokens:
    var fn next() Token?!:
        self.at += 1
        if self.at == self.fail_at: return error(Error("source failed", kind: "EIO"))
        if self.at <= 2: return ok(Token(self.at, self.log.clone()))

        return ok(none)

    var fn close() Unit!:
        return ok(unit)

fn events(log: String) String:
    if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")

    return ""

fn read_one(input: ReadStream[Token]) Unit!:
    var owned = input
    if token := try owned.next():
        try use_token(token)

fn wait_one(input: ReadStream[Token]) Unit!:
    var owned = input

    for item in owned:
        token := item
        try use_token(token)
        break

test "direct read keeps resource open through the body and closes once":
    dir := temporary("resource-read-") | try expect_ok
    log := "{dir.path()}/events"
    try read_one(ReadStream[Token](Tokens(log.clone())))
    try expect_equal(events(log), "body 1\nclose 1\n")

test "iterator keeps resource open through the body and closes once":
    dir := temporary("resource-wait-") | try expect_ok
    log := "{dir.path()}/events"
    try wait_one(ReadStream[Token](Tokens(log.clone())))
    try expect_equal(events(log), "body 1\nclose 1\n")

// A body uses the external log as well as the value's state: a duplicated resource can
// have `closed == false` while another copy already released the same external resource.
fn use_token(token: Token) Unit!:
    try expect_equal(token.closed, false)
    try expect_equal(events(token.log).contains("close {token.id}\n"), false)
    try append_file(token.log, "body {token.id}\n").wait()

fn close_item(input: Token) Unit!:
    var token = input
    try use_token(token)
    return token.close()

fn walk(log: String, action: Int) Unit!:
    var input = ReadStream[Token](Tokens(log.clone()))

    for item in input:
        if action == 5:
            try close_item(item)
            continue

        token := item
        try use_token(token)
        if action == 1: break
        if action == 2: return ok(unit)
        if action == 3: return error(Error("body failed", kind: "EBODY"))
        if action == 4: continue

        if action == 6:
            try input.close()

test "exhaustion and continue close each item after its body":
    dir := temporary("resource-exhaust-") | try expect_ok

    for action in [0, 4]:
        log := "{dir.path()}/{action}"
        try walk(log, action)
        try expect_equal(events(log), "body 1\nclose 1\nbody 2\nclose 2\n")

test "break return and error close the current item once":
    dir := temporary("resource-exit-") | try expect_ok

    for action in [1, 2, 3]:
        log := "{dir.path()}/{action}"
        result := walk(log, action)
        try expect_equal(result.is_error(), action == 3)
        try expect_equal(events(log), "body 1\nclose 1\n")

test "explicit item close and stream close preserve each item owner":
    dir := temporary("resource-close-") | try expect_ok
    item_closed := "{dir.path()}/5"
    try walk(item_closed, 5)
    try expect_equal(events(item_closed), "body 1\nclose 1\nbody 2\nclose 2\n")

    // Closing the stream ends it: the loop reads no further item.
    stream_closed := "{dir.path()}/6"
    try walk(stream_closed, 6)
    try expect_equal(events(stream_closed), "body 1\nclose 1\n")

fn source_error(log: String, fail_at: Int) Unit!:
    var input = ReadStream[Token](Tokens(log.clone(), fail_at: fail_at))

    for item in input:
        token := item
        try use_token(token)

test "a source error relays through try after closing earlier items":
    dir := temporary("resource-error-") | try expect_ok
    first := "{dir.path()}/first"
    reason := source_error(first, 1) | try expect_error
    try expect_equal(reason.kind, "EIO")
    try expect_equal(events(first), "")

    later := "{dir.path()}/later"
    later_reason := source_error(later, 2) | try expect_error
    try expect_equal(later_reason.kind, "EIO")
    try expect_equal(events(later), "body 1\nclose 1\n")

fn direct_next(log: String) Unit!:
    var input = ReadStream[Token](Tokens(log.clone()))

    if item := try input.next():
        token := item
        try use_token(token)

test "calling Waiting next directly transfers the item":
    dir := temporary("resource-next-") | try expect_ok
    log := "{dir.path()}/events"
    try direct_next(log)
    try expect_equal(events(log), "body 1\nclose 1\n")

type PlainTokens:
    log: String
    at: Int = 0

impl Iterator[Token] for PlainTokens:
    var fn next() Token?:
        self.at += 1
        if self.at <= 2: return Token(self.at, self.log.clone())

        return none

fn plain(log: String) Unit!:
    for token in PlainTokens(log.clone()):
        try use_token(token)

test "a custom Iterator transfers each freshly produced resource":
    dir := temporary("resource-plain-") | try expect_ok
    log := "{dir.path()}/events"
    try plain(log)
    try expect_equal(events(log), "body 1\nclose 1\nbody 2\nclose 2\n")

type OptionalTokens:
    log: String
    at: Int = 0

impl Source[Token?] for OptionalTokens:
    var fn next() Token??!:
        self.at += 1
        if self.at > 1: return ok(none)

        inner: Token? = Token(1, self.log.clone())
        return ok(inner)

    var fn close() Unit!:
        return ok(unit)

fn optional_payload(log: String) Unit!:
    var input = ReadStream[Token?](OptionalTokens(log.clone()))

    for item in input:
        maybe := item
        if token := maybe:
            try use_token(token)

test "a nested optional payload transfers its resource":
    dir := temporary("resource-optional-") | try expect_ok
    log := "{dir.path()}/events"
    try optional_payload(log)
    try expect_equal(events(log), "body 1\nclose 1\n")

type ResultTokens:
    log: String
    at: Int = 0

impl Source[Token!] for ResultTokens:
    var fn next() Result[Result[Token, Error]?, Error]:
        self.at += 1
        if self.at > 1: return ok(none)

        inner: Token! = ok(Token(1, self.log.clone()))
        return ok(inner)

    var fn close() Unit!:
        return ok(unit)

fn result_payload(log: String) Unit!:
    var input = ReadStream[Token!](ResultTokens(log.clone()))

    for item in input:
        token := try item
        try use_token(token)

test "a nested result payload transfers its resource":
    dir := temporary("resource-result-") | try expect_ok
    log := "{dir.path()}/events"
    try result_payload(log)
    try expect_equal(events(log), "body 1\nclose 1\n")

// Wait for the exact acquisition/body event before cancelling; the deadline bounds a failed handshake.
fn wait_for_event(log: String, expected: String) Unit!:
    for attempt in 0..1000:
        if events(log).contains(expected): return ok(unit)

        _ := sleep(milliseconds(10)).wait()

    return error(Error("resource handshake timed out", kind: "ETIMEDOUT"))

fn wait_cancelled(log: String) Unit!:
    var input = ReadStream[Token](Tokens(log.clone()))

    for item in input:
        token := item
        try use_token(token)

        _ := sleep(milliseconds(60000)).wait()

test "cancelling an active body closes the delivered item once":
    dir := temporary("resource-body-cancel-") | try expect_ok
    log := "{dir.path()}/events"
    work := promise(fn: wait_cancelled(log))
    try wait_for_event(log, "body 1\n")
    work.cancel()

    reason := work.wait() | try expect_error
    try expect_equal(reason.kind, "ECANCELED")
    try expect_equal(events(log), "body 1\nclose 1\n")

type PendingTokens:
    log: String

impl Source[Token] for PendingTokens:
    var fn next() Token?!:
        token := Token(1, self.log.clone())
        try append_file(self.log, "ready\n").wait()

        _ := sleep(milliseconds(60000)).wait()
        return ok(token)

    var fn close() Unit!:
        return ok(unit)

fn next_cancelled(log: String) Unit!:
    var input = ReadStream[Token](PendingTokens(log.clone()))

    for item in input:
        token := item
        try use_token(token)

test "cancelling a source step closes its undelivered item once":
    dir := temporary("resource-next-cancel-") | try expect_ok
    log := "{dir.path()}/events"
    work := promise(fn: next_cancelled(log))
    try wait_for_event(log, "ready\n")
    work.cancel()

    reason := work.wait() | try expect_error
    try expect_equal(reason.kind, "ECANCELED")
    try expect_equal(events(log), "ready\nclose 1\n")

fn resume_after_break(log: String) Unit!:
    var input = ReadStream[Token](Tokens(log.clone()))

    for item in input:
        token := item
        try use_token(token)
        break

    if token := try input.next():
        try use_token(token)

test "breaking returns the source so its next resource can be read":
    dir := temporary("resource-resume-") | try expect_ok
    log := "{dir.path()}/events"
    try resume_after_break(log)
    try expect_equal(events(log), "body 1\nclose 1\nbody 2\nclose 2\n")
