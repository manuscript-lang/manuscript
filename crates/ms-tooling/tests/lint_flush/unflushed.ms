import Closeable from "@std/core.ms"

type Journal:
    lines: Int

impl Closeable for Journal:
    var fn close() Unit!:
        _ := self.lines
        return ok(unit)

impl Journal:
    var fn flush() Result[Unit, Error]:
        return ok(unit)

export fn forgets() Int:
    journal := Journal(1)
    return journal.lines

export fn flushes() Result[Int, Error]:
    var journal = Journal(2)
    journal.flush()?
    return ok(journal.lines)

type Holder:
    journal: Journal

fn returns() Journal:
    journal := Journal(3)
    return journal

fn stores() Holder:
    journal := Journal(4)
    return Holder(journal)

export fn uses_moves() Int:
    return returns().lines + stores().journal.lines
