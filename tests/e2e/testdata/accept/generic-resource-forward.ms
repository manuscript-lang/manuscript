import Closeable, Iterator from "@std/core.ms"
import Source from "@std/io/io.ms"
import append_file, read_file, temporary from "@std/os/fs.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

type Token:
    log: String
    id: Int

impl Closeable for Token:
    var fn close() Unit!:
        try append_file(self.log, "close {self.id}\n")
        return ok(unit)

type Tokens:
    log: String
    at: Int = 0

impl Source[Token] for Tokens:
    var fn next() Token?!:
        self.at += 1
        if self.at <= 2:
            return ok(Token(self.log.clone(), self.at))

        return ok(none)

    var fn close() Unit!:
        return ok(unit)

type Forward[T]:
    source: Source[T]

impl Iterator[T!] for Forward[T]:
    var fn next() T!?:
        let result = self.source.next()
        if result.is_error():
            return error(result.err())
        if let item = result.get():
            return ok(item)

        return none

fn first_body(log: String) Unit!:
    for item in Forward[Token](Tokens(log.clone())):
        let token = try item
        try append_file(log, "body {token.id}\n")
        break

    return ok(unit)

fn events(log: String) String:
    if let bytes = read_file(log).wait():
        return bytes.decode_utf8().get("")

    return ""

test "a generic adapter forwards a resource through Result.get once":
    let dir = temporary("generic-forward-") | try expect_ok
    let log = "{dir.path()}/events"
    try first_body(log.clone())
    try expect_equal(events(log), "body 1\nclose 1\n")
