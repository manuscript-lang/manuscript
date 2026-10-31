import Closeable, TextError from "@std/core.ms"

type Journal:
    lines: Int

impl Closeable for Journal:
    var fn close() Unit!:
        let _ = self.lines
        return ok(unit)

impl Journal:
    var fn flush() Result[Unit, TextError]:
        return ok(unit)

export fn forgets() Int:
    let journal = Journal(1)
    return journal.lines

export fn flushes() Result[Int, TextError]:
    var journal = Journal(2)
    try journal.flush()
    return ok(journal.lines)

type Holder:
    journal: Journal

fn returns() Journal:
    let journal = Journal(3)
    return journal

fn stores() Holder:
    let journal = Journal(4)
    return Holder(journal)

export fn uses_moves() Int:
    return returns().lines + stores().journal.lines
