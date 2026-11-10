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

type Holder:
    journal: Journal

fn take(j: Journal) Holder:
    return Holder(j)

export fn kept_on_one_path(c: Bool) Int:
    journal := Journal(1)
    if c:
        return take(journal).journal.lines

    return 0

export fn moved_on_every_path(c: Bool) Int:
    journal := Journal(2)
    if c:
        return take(journal).journal.lines

    return take(journal).journal.lines

export fn moved_in_both_branches(c: Bool) Int:
    journal := Journal(3)

    if c:
        return take(journal).journal.lines
    else:
        return take(journal).journal.lines
